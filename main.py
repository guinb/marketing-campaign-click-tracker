import os
import asyncio
import hashlib
import json
import logging
from contextlib import asynccontextmanager
import html
from datetime import datetime
from urllib.parse import quote

import aiomysql
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import RedirectResponse, HTMLResponse
from user_agents import parse as parse_ua

# --- Logging ---
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "timestamp": self.formatTime(record, self.datefmt),
            "severity": record.levelname,
            "message": record.getMessage(),
            "service": "redirect-service",
        }
        if hasattr(record, 'json_fields'):
            log_record.update(record.json_fields)
        if record.exc_info:
            log_record['exc_info'] = self.formatException(record.exc_info)
        return json.dumps(log_record)

handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logger = logging.getLogger(__name__)

# --- Database ---
db_pool: aiomysql.Pool = None

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", 3306)),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "db": os.getenv("DB_NAME", "campaign_tracker"),
    "charset": "utf8mb4",
    "autocommit": True,
}

BASE_REDIRECT_URL = os.getenv("BASE_REDIRECT_URL", "http://localhost:8080").rstrip("/")


@asynccontextmanager
async def lifespan(app: FastAPI):
    global db_pool
    logger.info("Inicializando pool de conexões MySQL")
    db_pool = await aiomysql.create_pool(
        minsize=2,
        maxsize=10,
        **DB_CONFIG
    )
    logger.info("Pool MySQL pronto")
    yield
    db_pool.close()
    await db_pool.wait_closed()
    logger.info("Pool MySQL fechado")


app = FastAPI(
    title="Traah Redirect Service",
    version="1.0.0",
    lifespan=lifespan,
)


# --- Helpers ---
def get_client_ip(request: Request) -> str:
    """Extrai o IP real do cliente, respeitando proxies"""
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "0.0.0.0"


def compute_fingerprint(ip: str, user_agent: str) -> str:
    """Gera um hash para identificar o dispositivo de forma anônima"""
    raw = f"{ip}|{user_agent}"
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def detect_device_type(user_agent_string: str) -> str:
    """Detecta se o dispositivo é mobile, tablet ou desktop"""
    ua = parse_ua(user_agent_string)
    if ua.is_mobile:
        return "mobile"
    elif ua.is_tablet:
        return "tablet"
    return "desktop"


async def record_click(
    company_id: int,
    link_id: int,
    ip: str,
    user_agent: str,
    referer: str,
    device_type: str,
    fingerprint: str,
):
    """Registra o clique no banco de dados"""
    try:
        # TODO: GeoIP lookup para country_code
        country_code = None

        async with db_pool.acquire() as conn:
            async with conn.cursor() as cursor:
                await cursor.execute(
                    """
                    INSERT INTO tracking_clicks 
                        (company_id, link_id, click_fingerprint, ip_address, user_agent, referer, country_code, device_type)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (company_id, link_id, fingerprint, ip, user_agent[:500], referer[:1000] if referer else None, country_code, device_type)
                )
                await cursor.execute(
                    "UPDATE tracking_links SET click_count = click_count + 1 WHERE id = %s",
                    (link_id,)
                )
    except Exception as e:
        logger.error(f"Erro ao registrar clique: {e}", exc_info=True)


# --- Endpoints ---

@app.get("/health")
async def health_check():
    """Health check para load balancers e monitoramento"""
    return {"status": "ok", "service": "redirect", "timestamp": datetime.utcnow().isoformat()}


@app.get("/r/{slug}")
async def redirect_to_whatsapp(slug: str, request: Request):
    """
    Endpoint principal de redirect:
    1. Busca o link pelo slug
    2. Registra o clique (assíncrono)
    3. Redireciona 302 para wa.me
    """
    async with db_pool.acquire() as conn:
        async with conn.cursor(aiomysql.DictCursor) as cursor:
            await cursor.execute(
                """
                SELECT id, company_id, target_phone, prefilled_message 
                FROM tracking_links 
                WHERE slug = %s AND is_active = TRUE
                """,
                (slug,)
            )
            link = await cursor.fetchone()

    if not link:
        raise HTTPException(status_code=404, detail="Link não encontrado ou desativado")

    # Extrai dados do request
    ip = get_client_ip(request)
    user_agent = request.headers.get("User-Agent", "unknown")
    referer = request.headers.get("Referer", "")
    device_type = detect_device_type(user_agent)
    fingerprint = compute_fingerprint(ip, user_agent)

    # Registra o clique em background (não bloqueia o redirect)
    asyncio.create_task(
        record_click(
            company_id=link["company_id"],
            link_id=link["id"],
            ip=ip,
            user_agent=user_agent,
            referer=referer,
            device_type=device_type,
            fingerprint=fingerprint,
        )
    )

    # Monta a URL de destino
    phone = link["target_phone"]
    message = link.get("prefilled_message")
    
    if message:
        wa_url = f"https://wa.me/{phone}?text={quote(message)}"
    else:
        wa_url = f"https://wa.me/{phone}"

    log_entry = {
        "event": "redirect",
        "slug": slug,
        "company_id": link["company_id"],
        "device": device_type,
        "ip": ip,
    }
    logger.info("Clique registrado e redirecionado", extra={'json_fields': log_entry})

    return RedirectResponse(url=wa_url, status_code=302)


@app.get("/r/{slug}/preview")
async def link_preview(slug: str):
    """
    Retorna HTML com Open Graph tags para preview social:
    Quando alguém compartilha um link no WhatsApp/Instagram,
    aparece um preview visual em vez de uma URL crua
    """
    async with db_pool.acquire() as conn:
        async with conn.cursor(aiomysql.DictCursor) as cursor:
            await cursor.execute(
                """
                SELECT tl.target_phone, tl.prefilled_message, tl.slug, tc.name as campaign_name
                FROM tracking_links tl
                LEFT JOIN tracking_campaigns tc ON tl.campaign_id = tc.id
                WHERE tl.slug = %s AND tl.is_active = TRUE
                """,
                (slug,)
            )
            link = await cursor.fetchone()

    if not link:
        raise HTTPException(status_code=404, detail="Link não encontrado")

    raw_title = link.get("campaign_name") or "Fale conosco no WhatsApp"
    raw_desc = link.get("prefilled_message") or "Clique para iniciar uma conversa"
    
    title = html.escape(raw_title)
    description = html.escape(raw_desc[:200])
    redirect_url = html.escape(f"{BASE_REDIRECT_URL}/r/{slug}")

    code = f"""
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
        <meta charset="utf-8">
        <meta property="og:title" content="{title}" />
        <meta property="og:description" content="{description}" />
        <meta property="og:type" content="website" />
        <meta property="og:url" content="{redirect_url}" />
        <meta name="twitter:card" content="summary" />
        <meta name="twitter:title" content="{title}" />
        <meta name="twitter:description" content="{description}" />
        <meta http-equiv="refresh" content="0;url={redirect_url}" />
        <title>{title}</title>
    </head>
    <body>
        <p>Redirecionando... <a href="{redirect_url}">Clique aqui</a> se não for redirecionado automaticamente</p>
    </body>
    </html>
    """

    return HTMLResponse(content=code)
