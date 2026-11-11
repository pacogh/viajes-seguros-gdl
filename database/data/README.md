# Límites municipales incluidos

`../06_amg_boundaries.sql` contiene las geometrías de nueve municipios del AMG,
extraídas del conjunto **Límite Municipal Jalisco IIEG**, publicado por el
Instituto de Información Estadística y Geográfica de Jalisco. La ficha consultada
indica actualización del 6 de octubre de 2026 y licencia Creative Commons
Attribution 4.0. Fuente: https://seijal.jalisco.gob.mx/datos-abiertos/es/dataset/limite-municipal-jalisco-iieg

La capa original está en EPSG:6368 (Mexico ITRF2008 / UTM zone 13N). El SQL aplica
`ST_Transform` a EPSG:4326 al importar. El municipio se identifica por clave
geoestadística INEGI; nombres y claves quedan en el `INSERT` para atribución y
auditoría. Para redistribuir la geometría, conservar esta atribución y la licencia.

El conversor opcional sin dependencias externas está en
`../tools/convert_iieg_shapefile.py`. Recibe el directorio que contiene los
archivos `limite_municipal.shp` y `.dbf`, además de la ruta destino del SQL.

