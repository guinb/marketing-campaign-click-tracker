# Campaign Redirect & Click Tracking Service

[![Python Version](https://img.shields.io/badge/python-3.13-blue.svg)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115.0-009688.svg)](https://fastapi.tiangolo.com/)
[![Docker](https://img.shields.io/badge/docker-%232496ED.svg?logo=docker&logoColor=white)](https://www.docker.com/)
[![MySQL](https://img.shields.io/badge/mysql-%2300f.svg?logo=mysql&logoColor=white)](https://www.mysql.com/)

Um serviço de redirecionamento de links de alta performance e baixa latência focado no rastreamento de cliques e atribuição de campanhas para **Marketing Digital (Tráfego Pago e Orgânico)**.

---

## 📌 Contexto de Negócio e Narrativa do Projeto

Este projeto foi concebido para resolver um desafio comum enfrentado por equipes de Growth e Marketing Digital: **atribuição de conversão e rastreabilidade de leads no canal de atendimento (WhatsApp)**. 

Ao rodar campanhas pagas (como Google Search Ads e Facebook Ads) ou orgânicas (como links na bio do Instagram e parcerias com influenciadores no YouTube), as empresas frequentemente direcionam o usuário diretamente para links do WhatsApp (`wa.me`). Contudo, ao fazer isso, perde-se completamente o rastro de qual anúncio ou criativo originou o contato (o chamado *Analytics Black Hole*).

**A Solução:**
Este microsserviço atua como um redirecionador inteligente intermediário. Quando o lead clica no link curto (ex: `links.seu-dominio.com/r/bf-google`), a aplicação intercepta a requisição, analisa os metadados do visitante de forma anônima e o redireciona instantaneamente para a API do WhatsApp com o número e a mensagem pré-configurados.

Para garantir que o redirecionamento seja ultra-rápido, a gravação de dados no banco de dados ocorre em segundo plano (assincronamente via `asyncio.create_task`), evitando que o lead sofra com lentidão na transição.

---

## 📊 Modelagem do Banco de Dados (DER)

A estrutura relacional foi modelada para garantir integridade referencial ao mesmo tempo em que otimiza consultas de grande volume (OLAP) por meio de índices apropriados em campos de data, slug e fingerprint de dispositivos.

```mermaid
erDiagram
    TRACKING_CAMPAIGNS {
        int id PK
        varchar name "Nome da Campanha"
        varchar utm_source "Origem (ex: google)"
        varchar utm_medium "Meio (ex: cpc)"
        varchar utm_campaign "Código UTM Campaign"
        timestamp created_at
    }
    
    TRACKING_LINKS {
        int id PK
        int company_id
        int campaign_id FK "Relacionamento opcional"
        varchar slug UK "Identificador da URL"
        varchar target_phone "WhatsApp de destino"
        text prefilled_message "Mensagem padrão"
        int click_count "Cache de Cliques"
        boolean is_active
        timestamp created_at
    }

    TRACKING_CLICKS {
        bigint id PK
        int company_id
        int link_id FK "Relacionamento com links"
        varchar click_fingerprint "IP + UA anônimo"
        varchar ip_address "IPv4 ou IPv6"
        varchar user_agent "Navegador/SO"
        varchar referer "Origem física do clique"
        varchar country_code "Código país (GeoIP)"
        varchar device_type "mobile/desktop/tablet"
        timestamp clicked_at
    }

    TRACKING_CAMPAIGNS ||--o{ TRACKING_LINKS : "contém"
    TRACKING_LINKS ||--o{ TRACKING_CLICKS : "registra"
```

---

## 🛠️ Tecnologias Utilizadas

- **FastAPI (Python 3.13)**: Framework assíncrono de alto desempenho usado para expor os endpoints operacionais.
- **aiomysql / PyMySQL**: Comunicação assíncrona com o MySQL prevenindo gargalos de conexão.
- **MySQL 8.0**: Banco de dados relacional para persistência transacional e relatórios analíticos.
- **Docker & Docker Compose**: Containerização total do ambiente para fácil portabilidade e implantação local.
- **Python Data Stack (Pandas, Seaborn, Matplotlib)**: Utilizados no Jupyter Notebook para gerar relatórios visuais e estatísticas.

---

## 🚀 Como Executar o Projeto Localmente

Certifique-se de possuir o [Docker](https://www.docker.com/) instalado em sua máquina.

### 1. Clonar o repositório e preparar as variáveis de ambiente:
Copie as variáveis de exemplo para o seu arquivo local:
```bash
cp .env.example .env
```

### 2. Subir os containers (Aplicação + MySQL):
```bash
docker-compose up --build -d
```
*Nota: Na primeira execução, o MySQL irá rodar automaticamente o script [schema.sql](./schema.sql) localizado na pasta de inicialização para estruturar o banco de dados.*

### 3. Verificar o status dos serviços:
Acesse o endpoint de health check no navegador para verificar se a aplicação FastAPI está conectada ao banco:
- URL: `http://localhost:8080/health`

---

## 📈 Análise de Dados e Queries Analíticas

Como Analista de Dados, estruturei uma suíte de consultas analíticas SQL em [queries_analiticas.sql](./queries_analiticas.sql) para responder a dores de negócio reais, como:
1. **Total de Cliques vs. Cliques Únicos**: Identificar usuários reais por meio da métrica de `click_fingerprint`.
2. **Padrão de Distribuição Temporal**: Rastrear horários de pico para otimização de agendamento de anúncios de tráfego pago (Ad Scheduling).
3. **Métricas de Tráfego Pago vs. Orgânico**: Comparativo do share de engajamento entre anúncios pagos e links orgânicos.
4. **Análise de Intervalo de Acesso (Lealdade)**: Window functions que medem o tempo decorrido entre cliques recorrentes de um mesmo fingerprint.

### Visualização com Jupyter Notebook
Na pasta `notebooks/`, o arquivo [analise_cliques.ipynb](./notebooks/analise_cliques.ipynb) realiza uma análise exploratória completa simulando 1500 cliques de campanhas. O notebook está documentado para expor:
- Gráficos de barra comparativos de performance de campanhas.
- Share de cliques por meio de tráfego (gráfico de pizza).
- Tendências de acesso por hora e dia de semana (gráficos de linha).
- Conclusões acionáveis sobre a otimização de orçamentos e layouts de conversão.

---

## 📁 Estrutura de Diretórios
```text
├── notebooks/
│   └── analise_cliques.ipynb   # Análise Exploratória e Visualização de Dados
├── .env.example                # Template de configuração de variáveis
├── docker-compose.yml          # Orquestrador local do banco e da aplicação
├── Dockerfile                  # Build multi-stage otimizada da aplicação FastAPI
├── main.py                     # Lógica principal do FastAPI (redirecionamento e logs)
├── queries_analiticas.sql      # Queries SQL avançadas (CTEs, Window Functions, Agregações)
├── requirements.txt            # Dependências da aplicação
└── schema.sql                  # Modelagem física DDL do banco de dados MySQL
```
