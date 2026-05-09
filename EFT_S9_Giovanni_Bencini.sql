-- =====================================================================
-- PARTE 1: CONFIGURACIÓN INICIAL (EJECUTAR COMO ADMINISTRADOR / SYS)
-- =====================================================================
-- Objetivo: Crear la infraestructura de seguridad, usuarios y roles 
-- según los requerimientos del caso.

-- Habilitar creación de usuarios en entornos locales (Oracle XE)
ALTER SESSION SET "_ORACLE_SCRIPT"=true; 

-- 1. Creación de Usuarios con sus configuraciones de espacio y cuotas 
CREATE USER PRY2205_EFT IDENTIFIED BY "Duoc.2024_EFT"
DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE temp QUOTA 10M ON USERS;

CREATE USER PRY2205_EFT_DES IDENTIFIED BY "Duoc.2024_DES"
DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE temp QUOTA 10M ON USERS;

CREATE USER PRY2205_EFT_CON IDENTIFIED BY "Duoc.2024_CON"
DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE temp QUOTA 10M ON USERS;

-- 2. Creación de Roles para gestión de privilegios 
CREATE ROLE PRY2205_ROL_D;
CREATE ROLE PRY2205_ROL_C;

-- 3. Asignación de Privilegios de Sistema
-- Dueño: Permisos totales para administrar su esquema
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, 
      CREATE PUBLIC SYNONYM, CREATE SYNONYM, CREATE ANY INDEX TO PRY2205_EFT;

-- Desarrollador: Permisos para programar objetos (incluye corrección de privilegios directos) [cite: 17]
GRANT CREATE SESSION, CREATE SEQUENCE, CREATE PROCEDURE, CREATE VIEW TO PRY2205_EFT_DES;
GRANT PRY2205_ROL_D TO PRY2205_EFT_DES;

-- Consultor: Solo acceso a la sesión (lectura mediante roles) 
GRANT CREATE SESSION TO PRY2205_ROL_C;
GRANT PRY2205_ROL_C TO PRY2205_EFT_CON;


-- =====================================================================
-- PARTE 2: DUEÑO DE LOS DATOS (EJECUTAR COMO PRY2205_EFT)
-- =====================================================================
-- Objetivo: Administrar objetos base, reportes de tarjetas y sinónimos.

-- CASO 1: Sinónimos Públicos para seguridad y facilidad de acceso 
CREATE OR REPLACE PUBLIC SYNONYM SYN_DEUDOR FOR PRY2205_EFT.DEUDOR;
CREATE OR REPLACE PUBLIC SYNONYM SYN_OCUPACION FOR PRY2205_EFT.OCUPACION;
CREATE OR REPLACE PUBLIC SYNONYM SYN_TARJETA_DEUDOR FOR PRY2205_EFT.TARJETA_DEUDOR;
CREATE OR REPLACE PUBLIC SYNONYM SYN_CUOTA_TARJETAS FOR PRY2205_EFT.CUOTA_TARJETAS;
CREATE OR REPLACE PUBLIC SYNONYM SYN_TRANSACCION FOR PRY2205_EFT.TRANSACCION_TARJETA_DEUDOR;
CREATE OR REPLACE PUBLIC SYNONYM SYN_SUCURSAL FOR PRY2205_EFT.SUCURSAL;

-- CASO 3.1: Informe de Análisis de Tarjetas
-- Limpieza preventiva para asegurar ejecución limpia 
DROP TABLE T_ANALISIS_TARJETAS CASCADE CONSTRAINTS;
DROP SEQUENCE SEQ_T_ANALISIS;

-- Estructura de la tabla de reporte 
CREATE TABLE T_ANALISIS_TARJETAS (
    NUM_ANALISIS NUMBER PRIMARY KEY,
    NRO_TARJETA NUMBER(30),
    TOTAL_CUOTAS NUMBER(2),
    MONTO_TOTAL_TRANSA NUMBER(10),
    FECHA_TRANSACCION DATE,
    DIRECCION VARCHAR2(40),
    MONTO_REAJUSTADO NUMBER
);

CREATE SEQUENCE SEQ_T_ANALISIS START WITH 1 INCREMENT BY 1;

-- Carga de datos con reglas de negocio y reajustes 
-- Se usa subconsulta para permitir ORDER BY junto con secuencias 
INSERT INTO T_ANALISIS_TARJETAS (
    NUM_ANALISIS, NRO_TARJETA, TOTAL_CUOTAS, MONTO_TOTAL_TRANSA, FECHA_TRANSACCION, DIRECCION, MONTO_REAJUSTADO
)
SELECT SEQ_T_ANALISIS.NEXTVAL, Q.* FROM (
    SELECT TR.nro_tarjeta, TR.total_cuotas_transaccion, TR.monto_total_transaccion, 
           TR.fecha_transaccion, INITCAP(S.direccion),
           CASE 
               WHEN TR.monto_total_transaccion BETWEEN 200000 AND 300000 THEN ROUND(TR.monto_total_transaccion * 1.05)
               WHEN TR.monto_total_transaccion BETWEEN 300001 AND 500000 THEN ROUND(TR.monto_total_transaccion * 1.07)
               ELSE TR.monto_total_transaccion
           END
    FROM SYN_TRANSACCION TR
    JOIN SYN_SUCURSAL S ON TR.id_sucursal = S.id_sucursal
    WHERE UPPER(SUBSTR(S.direccion, 1, 1)) = 'A' AND TR.monto_total_transaccion >= 200000
    ORDER BY TR.nro_tarjeta ASC, 6 DESC
) Q;
COMMIT;

-- CASO 3.2: Índices para optimizar el acceso a datos 
CREATE INDEX IDX_SUCURSAL_DIR ON SUCURSAL(UPPER(SUBSTR(direccion, 1, 1)));
CREATE INDEX IDX_TRANSACCION_MONTO ON TRANSACCION_TARJETA_DEUDOR(monto_total_transaccion);

-- Permisos directos al Desarrollador con opción de compartir (GRANT OPTION) 
GRANT SELECT ON DEUDOR TO PRY2205_EFT_DES WITH GRANT OPTION;
GRANT SELECT ON OCUPACION TO PRY2205_EFT_DES WITH GRANT OPTION;
GRANT SELECT ON TARJETA_DEUDOR TO PRY2205_EFT_DES WITH GRANT OPTION;
GRANT SELECT ON CUOTA_TARJETAS TO PRY2205_EFT_DES WITH GRANT OPTION;

-- Permiso directo al Consultor para leer la tabla de análisis
GRANT SELECT ON T_ANALISIS_TARJETAS TO PRY2205_EFT_CON;

-- =====================================================================
-- PARTE 3: DESARROLLADOR (EJECUTAR COMO PRY2205_EFT_DES)
-- =====================================================================
-- Objetivo: Generar la vista de análisis de deudores del periodo.

CREATE OR REPLACE VIEW VW_ANALISIS_DEUDORES_PERIODO AS
SELECT 
    TO_CHAR(D.numrun, 'FM99G999G999', 'NLS_NUMERIC_CHARACTERS='',.''') || '-' || D.dvrun AS "RUT_DEUDOR",
    INITCAP(D.pnombre || ' ' || D.appaterno || ' ' || D.apmaterno) AS "NOMBRE DEUDOR",
    COUNT(C.nro_cuota) AS "TOTAL_CUOTAS",
    ROUND(AVG(C.valor_cuota)) AS "PROMEDIO_VALOR_CUOTAS",
    TO_CHAR(MIN(C.fecha_venc_cuota), 'DD-MM-YYYY') AS "FECHA_MAS_ANTIGUA",
    NVL(TO_CHAR(D.fono_contacto), 'Sin Información') AS "TELEFONO",
    UPPER(O.nombre_prof_ofic) AS "OCUPACION",
    T.cupo_disp_compra AS "CUPO_DISP_COMPRA"
FROM SYN_DEUDOR D
JOIN SYN_OCUPACION O ON D.cod_ocupacion = O.cod_ocupacion
JOIN SYN_TARJETA_DEUDOR T ON D.numrun = T.numrun
JOIN SYN_CUOTA_TARJETAS C ON T.nro_tarjeta = C.nro_tarjeta
WHERE UPPER(O.nombre_prof_ofic) NOT LIKE '%INGENIERO%'
  AND EXTRACT(YEAR FROM C.fecha_venc_cuota) = EXTRACT(YEAR FROM SYSDATE) - 1
GROUP BY D.numrun, D.dvrun, D.pnombre, D.appaterno, D.apmaterno, D.fono_contacto, O.nombre_prof_ofic, T.cupo_disp_compra
HAVING AVG(C.valor_cuota) < (SELECT MAX(AVG(valor_cuota)) FROM SYN_CUOTA_TARJETAS GROUP BY nro_tarjeta)
ORDER BY "TOTAL_CUOTAS" ASC, "CUPO_DISP_COMPRA" ASC;

-- Compartir el resultado final con el Consultor [cite: 18]
GRANT SELECT ON VW_ANALISIS_DEUDORES_PERIODO TO PRY2205_EFT_CON;


-- =====================================================================
-- PARTE 4: CONSULTOR (EJECUTAR COMO PRY2205_EFT_CON)
-- =====================================================================
-- Objetivo: Verificación final de los reportes generados[cite: 19].

-- Comprobar informe de Deudores (Vista)
SELECT * FROM PRY2205_EFT_DES.VW_ANALISIS_DEUDORES_PERIODO;

-- Comprobar informe de Tarjetas (Tabla mediante sinónimo público)
SELECT * FROM PRY2205_EFT.T_ANALISIS_TARJETAS;
