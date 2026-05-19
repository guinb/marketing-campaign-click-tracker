-- ==============================================================================
-- CONSULTAS PARA MONITORAMENTO DE CAMPANHAS E DESEMPENHO
-- ==============================================================================
-- Este arquivo contém consultas SQL típicas criadas para extrair insights sobre campanhas
-- de Tráfego Pago vs Orgânico, comportamento do consumidor e distribuição tecnológica
-- ==============================================================================

USE campaign_tracker;

-- ------------------------------------------------------------------------------
-- 1. VISÃO GERAL DAS CAMPANHAS
-- Medir o total de cliques, cliques únicos e 
-- a taxa de cliques repetidos (estimativa)
-- ------------------------------------------------------------------------------
WITH click_metrics AS (
    SELECT 
        c.id AS campaign_id,
        c.name AS campaign_name,
        c.utm_source,
        c.utm_medium,
        COUNT(cl.id) AS total_clicks,
        COUNT(DISTINCT cl.click_fingerprint) AS unique_clicks
    FROM tracking_campaigns c
    LEFT JOIN tracking_links l ON l.campaign_id = c.id
    LEFT JOIN tracking_clicks cl ON cl.link_id = l.id
    GROUP BY c.id, c.name, c.utm_source, c.utm_medium
)
SELECT 
    campaign_name,
    utm_source AS origem,
    utm_medium AS meio,
    total_clicks AS total_cliques,
    unique_clicks AS cliques_unicos,
    ROUND((unique_clicks / NULLIF(total_clicks, 0)) * 100, 2) AS pct_cliques_unicos,
    ROUND(((total_clicks - unique_clicks) / NULLIF(total_clicks, 0)) * 100, 2) AS pct_recorrencia
FROM click_metrics
ORDER BY total_cliques DESC;


-- ------------------------------------------------------------------------------
-- 2. ANÁLISE TEMPORAL E HORÁRIOS DE PICO
-- Identificar em quais horas do dia e dias da semana há maior volume
-- ------------------------------------------------------------------------------
SELECT 
    DAYNAME(clicked_at) AS dia_semana,
    HOUR(clicked_at) AS hora_dia,
    COUNT(*) AS total_cliques,
    COUNT(DISTINCT click_fingerprint) AS cliques_unicos
FROM tracking_clicks
GROUP BY DAYOFWEEK(clicked_at), DAYNAME(clicked_at), HOUR(clicked_at)
ORDER BY FIELD(dia_semana, 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'), hora_dia;


-- ------------------------------------------------------------------------------
-- 3. PERFIL TECNOLÓGICO DO PÚBLICO-ALVO
-- Mapear a distribuição de cliques por tipo de dispositivo e sistemas móveis vs desktop
-- ------------------------------------------------------------------------------
SELECT 
    device_type AS tipo_dispositivo,
    COUNT(*) AS total_cliques,
    ROUND((COUNT(*) * 100.0 / (SELECT COUNT(*) FROM tracking_clicks)), 2) AS representatividade_pct
FROM tracking_clicks
GROUP BY device_type
ORDER BY total_cliques DESC;


-- ------------------------------------------------------------------------------
-- 4. TRÁFEGO PAGO VS. TRÁFEGO ORGÂNICO
-- Avaliar o ROI agregando campanhas em canais Pagos e Orgânicos
-- ------------------------------------------------------------------------------
SELECT 
    CASE 
        WHEN LOWER(c.utm_medium) IN ('cpc', 'cpm', 'paid', 'ads', 'sponsored') OR LOWER(c.utm_source) LIKE '%ads%' THEN 'Tráfego Pago'
        ELSE 'Tráfego Orgânico'
    END AS canal_macro,
    COUNT(DISTINCT c.id) AS qtd_campanhas_ativas,
    COUNT(cl.id) AS cliques_totais,
    COUNT(DISTINCT cl.click_fingerprint) AS cliques_unicos,
    ROUND((COUNT(cl.id) * 100.0 / (SELECT COUNT(*) FROM tracking_clicks)), 2) AS share_cliques_pct
FROM tracking_campaigns c
INNER JOIN tracking_links l ON l.campaign_id = c.id
INNER JOIN tracking_clicks cl ON cl.link_id = l.id
GROUP BY 1
ORDER BY cliques_totais DESC;


-- ------------------------------------------------------------------------------
-- 5. COMPORTAMENTO DE REPETIÇÃO
-- Mapear o tempo médio que um mesmo usuário leva 
-- para clicar novamente em algum link de campanha.
-- ------------------------------------------------------------------------------
WITH clicks_sequenciais AS (
    SELECT 
        click_fingerprint,
        clicked_at,
        LAG(clicked_at) OVER (PARTITION BY click_fingerprint ORDER BY clicked_at) AS clique_anterior
    FROM tracking_clicks
)
SELECT 
    click_fingerprint,
    COUNT(*) AS total_cliques_usuario,
    MIN(clicked_at) AS primeiro_clique,
    MAX(clicked_at) AS ultimo_clique,
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, clique_anterior, clicked_at)), 1) AS intervalo_medio_minutos
FROM clicks_sequenciais
WHERE clique_anterior IS NOT NULL
GROUP BY click_fingerprint
HAVING total_cliques_usuario > 1
ORDER BY total_cliques_usuario DESC
LIMIT 50;
