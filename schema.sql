-- ==============================================================================
-- MODELAGEM DE BANCO DE DADOS
-- ==============================================================================

-- Criação do banco de dados
CREATE DATABASE IF NOT EXISTS campaign_tracker
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE campaign_tracker;

-- Metadados de campanhas de tráfego
CREATE TABLE IF NOT EXISTS tracking_campaigns (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL COMMENT 'Nome da campanha',
    utm_source VARCHAR(100) NOT NULL COMMENT 'Origem do tráfego',
    utm_medium VARCHAR(100) NOT NULL COMMENT 'Meio do tráfego',
    utm_campaign VARCHAR(100) NULL COMMENT 'UTM Campaign',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Índices para otimização de filtros
    INDEX idx_campaign_source_medium (utm_source, utm_medium)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Links de redirecionamento
CREATE TABLE IF NOT EXISTS tracking_links (
    id INT AUTO_INCREMENT PRIMARY KEY,
    company_id INT NOT NULL COMMENT 'Cliente/empresa',
    campaign_id INT NULL COMMENT 'Chave estrangeira para a campanha',
    slug VARCHAR(100) NOT NULL COMMENT 'URL curta',
    target_phone VARCHAR(20) NOT NULL COMMENT 'Telefone de destino com DDI e DDD (ex: 5511999999999)',
    prefilled_message TEXT NULL COMMENT 'Mensagem pré-preenchida',
    click_count INT DEFAULT 0 NOT NULL COMMENT 'Contador de cliques',
    is_active BOOLEAN DEFAULT TRUE NOT NULL COMMENT 'Flag para ativação/desativação do link',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uq_link_slug (slug),
    CONSTRAINT fk_links_campaign_id FOREIGN KEY (campaign_id) 
        REFERENCES tracking_campaigns (id) ON DELETE SET NULL,
        
    -- Índices de busca
    INDEX idx_links_slug_active (slug, is_active),
    INDEX idx_links_company (company_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Logs de cada clique
CREATE TABLE IF NOT EXISTS tracking_clicks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    company_id INT NOT NULL COMMENT 'Cliente/empresa',
    link_id INT NOT NULL COMMENT 'Chave estrangeira do link',
    click_fingerprint VARCHAR(32) NOT NULL COMMENT 'Hash anônimo (IP + User-Agent)',
    ip_address VARCHAR(45) NOT NULL COMMENT 'Endereço IP',
    user_agent VARCHAR(500) NOT NULL COMMENT 'Navegador/dispositivo',
    referer VARCHAR(1000) NULL COMMENT 'URL da origem',
    country_code VARCHAR(5) NULL COMMENT 'Código de país (TODO: GeoIP)',
    device_type VARCHAR(50) NOT NULL COMMENT 'Tipo do dispositivo',
    clicked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_clicks_link_id FOREIGN KEY (link_id) 
        REFERENCES tracking_links (id) ON DELETE CASCADE,
        
    -- Índices para consultas
    INDEX idx_clicks_link_time (link_id, clicked_at),
    INDEX idx_clicks_time (clicked_at),
    INDEX idx_clicks_fingerprint (click_fingerprint),
    INDEX idx_clicks_device (device_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
