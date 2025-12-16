-- =============================================================================
-- Plataforma de Prevención de Incendios - Inicialización de Base de Datos
-- Generado por el Instalador de Plataforma IoT v2.3
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE DATABASE IF NOT EXISTS `fire_preventionf` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `fire_preventionf`;

-- =============================================================================
-- TABLAS: Sistema RBAC
-- =============================================================================

DROP TABLE IF EXISTS `rol`;
CREATE TABLE `rol` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`nombre`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `permiso`;
CREATE TABLE `permiso` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `rol_permiso`;
CREATE TABLE `rol_permiso` (
  `id` int NOT NULL AUTO_INCREMENT,
  `role_id` int NOT NULL,
  `permiso_id` int NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_role_permission` (`role_id`,`permiso_id`),
  KEY `permission_id` (`permiso_id`),
  CONSTRAINT `role_permissions_ibfk_1` FOREIGN KEY (`role_id`) REFERENCES `rol` (`id`) ON DELETE CASCADE,
  CONSTRAINT `role_permissions_ibfk_2` FOREIGN KEY (`permiso_id`) REFERENCES `permiso` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLAS: Almacenamiento de Contraseñas (Separado por Seguridad)
-- =============================================================================

DROP TABLE IF EXISTS `pasadmin`;
CREATE TABLE `pasadmin` (
  `id` int NOT NULL AUTO_INCREMENT,
  `hashed_password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `encryption_key` varbinary(64) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `pasusuario`;
CREATE TABLE `pasusuario` (
  `id` int NOT NULL AUTO_INCREMENT,
  `hashed_password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `encryption_key` varbinary(64) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `pasgerente`;
CREATE TABLE `pasgerente` (
  `id` int NOT NULL AUTO_INCREMENT,
  `hashed_password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `encryption_key` varbinary(64) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `pasdispositivo`;
CREATE TABLE `pasdispositivo` (
  `id` int NOT NULL AUTO_INCREMENT,
  `api_key` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `encryption_key` varbinary(64) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_key` (`api_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLAS: Entidades Principales
-- =============================================================================

DROP TABLE IF EXISTS `admin`;
CREATE TABLE `admin` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `rol_id` int DEFAULT NULL,
  `pasadmin_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `rol_id` (`rol_id`),
  KEY `pasadmin_id` (`pasadmin_id`),
  CONSTRAINT `admins_ibfk_1` FOREIGN KEY (`rol_id`) REFERENCES `rol` (`id`),
  CONSTRAINT `admins_ibfk_2` FOREIGN KEY (`pasadmin_id`) REFERENCES `pasadmin` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `gerente`;
CREATE TABLE `gerente` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `admin_id` int DEFAULT NULL,
  `pasgerente_id` int DEFAULT NULL,
  `rol_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `admin_id` (`admin_id`),
  KEY `pasgerente_id` (`pasgerente_id`),
  KEY `rol_id` (`rol_id`),
  CONSTRAINT `gerentes_ibfk_1` FOREIGN KEY (`admin_id`) REFERENCES `admin` (`id`),
  CONSTRAINT `gerentes_ibfk_2` FOREIGN KEY (`pasgerente_id`) REFERENCES `pasgerente` (`id`),
  CONSTRAINT `gerentes_ibfk_3` FOREIGN KEY (`rol_id`) REFERENCES `rol` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `usuario`;
CREATE TABLE `usuario` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `rol_id` int DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT '1',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `pasusuario_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `rol_id` (`rol_id`),
  KEY `pasusuario_id` (`pasusuario_id`),
  CONSTRAINT `users_ibfk_1` FOREIGN KEY (`rol_id`) REFERENCES `rol` (`id`),
  CONSTRAINT `users_ibfk_2` FOREIGN KEY (`pasusuario_id`) REFERENCES `pasusuario` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `dispositivo`;
CREATE TABLE `dispositivo` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `device_type` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_active` tinyint(1) DEFAULT '1',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `admin_id` int DEFAULT NULL,
  `pasdispositivo_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `admin_id` (`admin_id`),
  KEY `pasdispositivo_id` (`pasdispositivo_id`),
  CONSTRAINT `dispositivos_ibfk_1` FOREIGN KEY (`admin_id`) REFERENCES `admin` (`id`),
  CONSTRAINT `dispositivos_ibfk_2` FOREIGN KEY (`pasdispositivo_id`) REFERENCES `pasdispositivo` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLAS: Servicios y Aplicaciones
-- =============================================================================

DROP TABLE IF EXISTS `servicio`;
CREATE TABLE `servicio` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `descripcion` text COLLATE utf8mb4_unicode_ci,
  `fecha_inicio` datetime NOT NULL,
  `fecha_fin` datetime DEFAULT NULL,
  `estado` enum('conectado','desconectado') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `gerente_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `gerente_id` (`gerente_id`),
  CONSTRAINT `servicios_ibfk_1` FOREIGN KEY (`gerente_id`) REFERENCES `gerente` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `app`;
CREATE TABLE `app` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `version` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `url` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `admin_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `admin_id` (`admin_id`),
  CONSTRAINT `apps_ibfk_1` FOREIGN KEY (`admin_id`) REFERENCES `admin` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLAS: Tablas de Unión (Muchos-a-Muchos)
-- =============================================================================

DROP TABLE IF EXISTS `servicio_dispositivo`;
CREATE TABLE `servicio_dispositivo` (
  `id` int NOT NULL AUTO_INCREMENT,
  `fecha_asignacion` datetime DEFAULT CURRENT_TIMESTAMP,
  `admin_id` int DEFAULT NULL,
  `servicio_id` int DEFAULT NULL,
  `dispositivo_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `admin_id` (`admin_id`),
  KEY `servicio_id` (`servicio_id`),
  KEY `dispositivo_id` (`dispositivo_id`),
  CONSTRAINT `sd_ibfk_1` FOREIGN KEY (`admin_id`) REFERENCES `admin` (`id`),
  CONSTRAINT `sd_ibfk_2` FOREIGN KEY (`servicio_id`) REFERENCES `servicio` (`id`),
  CONSTRAINT `sd_ibfk_3` FOREIGN KEY (`dispositivo_id`) REFERENCES `dispositivo` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `servicio_app`;
CREATE TABLE `servicio_app` (
  `id` int NOT NULL AUTO_INCREMENT,
  `fecha_asignacion` datetime DEFAULT CURRENT_TIMESTAMP,
  `admin_id` int DEFAULT NULL,
  `servicio_id` int DEFAULT NULL,
  `app_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `admin_id` (`admin_id`),
  KEY `servicio_id` (`servicio_id`),
  KEY `app_id` (`app_id`),
  CONSTRAINT `sa_ibfk_1` FOREIGN KEY (`admin_id`) REFERENCES `admin` (`id`),
  CONSTRAINT `sa_ibfk_2` FOREIGN KEY (`servicio_id`) REFERENCES `servicio` (`id`),
  CONSTRAINT `sa_ibfk_3` FOREIGN KEY (`app_id`) REFERENCES `app` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `usuario_servicio`;
CREATE TABLE `usuario_servicio` (
  `id` int NOT NULL AUTO_INCREMENT,
  `fecha_asignacion` datetime DEFAULT CURRENT_TIMESTAMP,
  `usuario_id` int DEFAULT NULL,
  `servicio_id` int DEFAULT NULL,
  `gerente_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `usuario_id` (`usuario_id`),
  KEY `servicio_id` (`servicio_id`),
  KEY `gerente_id` (`gerente_id`),
  CONSTRAINT `us_ibfk_1` FOREIGN KEY (`usuario_id`) REFERENCES `usuario` (`id`),
  CONSTRAINT `us_ibfk_2` FOREIGN KEY (`servicio_id`) REFERENCES `servicio` (`id`),
  CONSTRAINT `us_ibfk_3` FOREIGN KEY (`gerente_id`) REFERENCES `gerente` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- DATOS: Roles
-- =============================================================================

INSERT INTO `rol` (`id`, `nombre`, `description`) VALUES
(1, 'admin_master', 'Administrador maestro con permisos completos'),
(2, 'admin_normal', 'Administrador con permisos limitados'),
(3, 'user', 'Usuario final con acceso básico'),
(4, 'manager', 'Gerente con permisos operativos');

-- =============================================================================
-- DATOS: Permisos
-- =============================================================================

INSERT INTO `permiso` (`id`, `name`, `description`) VALUES
(1, 'create_user', 'Crear nuevos usuarios'),
(2, 'edit_user', 'Editar usuarios existentes'),
(3, 'delete_user', 'Eliminar usuarios'),
(4, 'create_service', 'Crear servicios'),
(5, 'assign_device', 'Asignar dispositivos a servicios'),
(6, 'view_reports', 'Ver reportes'),
(7, 'view_all_users', 'Listar todos los usuarios'),
(8, 'create_manager', 'Crear nuevos gerentes'),
(9, 'edit_manager', 'Editar gerentes existentes'),
(10, 'delete_manager', 'Eliminar gerentes'),
(11, 'create_admin', 'Crear nuevos administradores'),
(12, 'manage_roles', 'Gestionar roles y permisos'),
(13, 'grant_permissions', 'Otorgar permisos a otros roles'),
(14, 'create_device', 'Crear dispositivos IoT'),
(15, 'edit_device', 'Editar dispositivos'),
(16, 'delete_device', 'Eliminar dispositivos');

-- =============================================================================
-- DATOS: Asignaciones Rol-Permiso
-- =============================================================================

-- admin_master: TODOS los permisos
INSERT INTO `rol_permiso` (`role_id`, `permiso_id`) VALUES
(1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8),
(1, 9), (1, 10), (1, 11), (1, 12), (1, 13), (1, 14), (1, 15), (1, 16);

-- admin_normal: operaciones básicas
INSERT INTO `rol_permiso` (`role_id`, `permiso_id`) VALUES
(2, 4), (2, 5), (2, 6), (2, 7);

-- manager: operacional + crear usuarios
INSERT INTO `rol_permiso` (`role_id`, `permiso_id`) VALUES
(4, 1), (4, 4), (4, 5), (4, 6), (4, 7);

-- user: solo visualización
INSERT INTO `rol_permiso` (`role_id`, `permiso_id`) VALUES
(3, 6), (3, 7);

-- =============================================================================
-- DATOS: Usuarios de Prueba (Contraseñas con Hash Argon2)
-- =============================================================================

-- Admin Master: {{ADMIN_EMAIL}} / [contraseña personalizada]
INSERT INTO `pasadmin` (`id`, `hashed_password`, `encryption_key`) VALUES
(1, '{{ADMIN_PASSWORD_HASH}}', NULL);

INSERT INTO `admin` (`id`, `nombre`, `email`, `rol_id`, `pasadmin_id`) VALUES
(1, 'Admin Master', '{{ADMIN_EMAIL}}', 1, 1);

-- Manager: gerente@fire.com / password123 (usuario de prueba)
INSERT INTO `pasgerente` (`id`, `hashed_password`, `encryption_key`) VALUES
(1, '{{MANAGER_PASSWORD_HASH}}', NULL);

INSERT INTO `gerente` (`id`, `nombre`, `email`, `admin_id`, `pasgerente_id`, `rol_id`) VALUES
(1, 'Gerente Principal', 'gerente@fire.com', 1, 1, 4);

-- User: user@fire.com / password123 (usuario de prueba)
INSERT INTO `pasusuario` (`id`, `hashed_password`, `encryption_key`) VALUES
(1, '{{USER_PASSWORD_HASH}}', NULL);

INSERT INTO `usuario` (`id`, `nombre`, `email`, `rol_id`, `is_active`, `pasusuario_id`) VALUES
(1, 'Usuario Test', 'user@fire.com', 3, 1, 1);

-- Device: sensor-test-001 / TEST_DEVICE_API_KEY_32_CHARS_XX
INSERT INTO `pasdispositivo` (`id`, `api_key`, `encryption_key`) VALUES
(1, 'TEST_DEVICE_API_KEY_32_CHARS_XX', UNHEX('0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF'));

INSERT INTO `dispositivo` (`id`, `nombre`, `device_type`, `is_active`, `admin_id`, `pasdispositivo_id`) VALUES
(1, 'sensor-test-001', 'temperatura', 1, 1, 1);

-- =============================================================================
-- FIN
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Base de datos inicializada exitosamente' AS status;
