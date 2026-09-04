# CheckLinks

Léelo en otros idiomas: [Русский](README.md) · [English](README.en.md) · [Français](README.fr.md)

---

## Sobre el proyecto

**CheckLinks** es una utilidad de línea de comandos (CLI) escrita en **Zig** para comprobar los enlaces de una página web.

La utilidad carga la página HTML en la URL indicada, recopila todos los enlaces (`<a href>`) e imágenes (`<img src>`), y luego comprueba la disponibilidad de cada URL. El resultado se muestra en pantalla en forma de tabla o se exporta a un archivo CSV.

> El proyecto es una reescritura de una [implementación en PHP](https://gitverse.ru/kvt/check-links) existente anteriormente.

## Funcionalidades

- Carga de páginas mediante los esquemas `http://`, `https://` y `file://` (lectura de un archivo HTML local).
- Extracción de URL de los atributos `href` de las etiquetas `<a>` y `src` de las etiquetas `<img>`.
- Normalización de enlaces relativos a absolutos basándose en el dominio base (incluidos los enlaces relativos al protocolo `//`).
- Eliminación de URL duplicadas.
- Comprobación concurrente de la disponibilidad de cada URL mediante el método `HEAD` (un hilo por URL).
- Comprobación de URL en lotes de tamaño configurable: el número de solicitudes paralelas se define mediante `--parallels` (por defecto 5; de forma concurrente dentro de un lote y secuencial entre lotes).
- Cliente HTTP HEAD propio con soporte TLS y tiempo de espera de la solicitud (15 segundos por defecto, configurable mediante `--timeout`).
- Cabeceras HTTP personalizadas repetibles para páginas autenticadas y enlaces del mismo origen.
- Agrupación de resultados por código de respuesta HTTP.
- Salida en terminal en forma de tabla con códigos codificados por colores:
  - `2xx` — verde;
  - `3xx` — amarillo;
  - `4xx`/`5xx` — rojo.
- Exportación de resultados a un archivo CSV (delimitador `;`).
- Modo «solo errores» — muestra únicamente los enlaces fallidos.
- Barra de progreso del proceso de comprobación.
- Internacionalización de la interfaz: la ayuda CLI, los mensajes de error y advertencia, las cabeceras de la tabla y del CSV, así como la plantilla de la barra de progreso, se compilan en ruso, inglés, español o francés mediante la opción de compilación `-Dlocale` (por defecto `ru`).
- Generación de un script de autocompletado de la línea de comandos mediante el subcomando `completion`. Se admiten las shells `bash`, `zsh`, `fish` y `nushell`.
- Manejo explícito de errores de la aplicación en la función `main`: los errores de análisis de argumentos, inicialización del analizador, cabeceras y generación del script de autocompletado se muestran como un mensaje localizado en stderr, y el proceso finaliza con un código de retorno distinto de cero.

## Requisitos

- **Zig 0.16.0** o posterior (véase `minimum_zig_version` en [`build.zig.zon`](build.zig.zon)).

Dependencias externas del proyecto:

- [`args.zig`](https://github.com/ktarasov/args.zig) (0.0.9) — análisis de argumentos de línea de comandos; proporciona subcomandos y generación de scripts de autocompletado.
- `zigquery` (0.2.0) — analizador HTML para extraer `href`/`src`.

## Instalación y compilación

Clona el repositorio y compila el proyecto:

```sh
zig build
```

El archivo binario aparecerá en `zig-out/bin/`.

### Comandos de compilación

| Comando | Descripción |
| --- | --- |
| `zig build` | Compila el archivo ejecutable (`check_links`). |
| `zig build run -- <argumentos>` | Compila y ejecuta la utilidad. |
| `zig build test` | Ejecuta todas las pruebas. |
| `zig build release` | Compila los binarios de la versión final (archivos comprimidos) para varias plataformas. |
| `zig build -Dlocale=ru` | Compila con la interfaz en ruso (por defecto). |
| `zig build -Dlocale=en` | Compila con la interfaz en inglés. |
| `zig build -Dlocale=es` | Compila con la interfaz en español. |
| `zig build -Dlocale=fr` | Compila con la interfaz en francés. |

### Plataformas admitidas para la compilación de la versión final

`zig build release` compila y empaqueta binarios para:

- `x86_64-linux`
- `x86_64-windows` (archivo `.zip`)
- `x86_64-macos`
- `aarch64-macos`

### Localización

La interfaz de la utilidad (ayuda CLI, mensajes de error y advertencia, cabeceras de la tabla y del CSV, plantilla de la barra de progreso) se puede compilar en ruso, inglés, español o francés. El idioma se define en el momento de la compilación mediante la opción `-Dlocale` (por defecto — ruso):

```sh
zig build -Dlocale=ru   # interfaz en ruso (por defecto)
zig build -Dlocale=en   # interfaz en inglés
zig build -Dlocale=es   # interfaz en español
zig build -Dlocale=fr   # interfaz en francés
```

Los textos de localización se guardan en el catálogo tipado [`src/i18n.zig`](src/i18n.zig); la integridad de las claves para cada idioma está garantizada por el compilador.

## Uso

```sh
check_links <URL> [opciones]
```

### Parámetros

| Argumento | Descripción |
| --- | --- |
| `<URL>` | URL de la página cuyos enlaces hay que comprobar (obligatorio). |
| `-f`, `--fail` | Mostrar solo los enlaces con errores. |
| `-e`, `--export <archivo>` | Exportar los resultados a un archivo CSV. |
| `-t`, `--timeout <segundos>` | Tiempo de espera de la solicitud en segundos (por defecto 15; `0` — sin tiempo de espera). |
| `-H`, `--header <NAME: VALUE>` | Añadir una cabecera HTTP; la opción se puede repetir. |
| `-p`, `--parallels <cantidad>` | Número de solicitudes paralelas (por defecto 5; de 1 a 100). |

### Subcomando `completion`

Genera un script de autocompletado para el entorno en el que se ejecuta la utilidad. El tipo de shell se detecta automáticamente mediante la variable de entorno `$SHELL`. Se admiten `bash`, `zsh`, `fish` y `nushell`.

```sh
check_links completion
```

El script se escribe en el flujo de salida estándar, por lo que puedes redirigirlo al archivo de carga automática de tu shell:

```sh
# bash
check_links completion > ~/.bash_completion

# zsh
check_links completion > ${fpath[1]}/_check_links

# fish
check_links completion > ~/.config/fish/completions/check_links.fish

# nushell
check_links completion > check_links-completions.nu
```

Si no se puede determinar el tipo de shell o se produce un error durante la generación, la utilidad muestra un mensaje de error en stderr y finaliza con un código de retorno distinto de cero.

### Ejemplos

```sh
# Comprobar todos los enlaces de la página y mostrar la tabla en la terminal
check_links https://example.com/

# Generar un script de autocompletado para la shell actual
check_links completion

# Mostrar solo los enlaces con errores
check_links --fail https://example.com/

# Aumentar el tiempo de espera de la solicitud a 60 segundos
check_links --timeout 60 https://example.com/

# Aumentar el número de solicitudes paralelas (por ejemplo, a 20)
check_links --parallels 20 https://example.com/

# Exportar los resultados a un archivo CSV
check_links --export result.csv https://example.com/

# Exportar solo los enlaces con errores a CSV
check_links --fail --export errors.csv https://example.com/

# Comprobar una página autenticada con varias cabeceras
check_links -H 'Authorization: Bearer token' \
  --header 'X-Tenant-ID: 42' \
  https://example.com/private
```

Las cabeceras se envían al cargar la página de origen y al hacer solicitudes `HEAD` a enlaces con el mismo origen (esquema, host y puerto efectivo). No se envían al redirigir a un origen externo ni al comprobarlo. Se admiten las formas `--header 'NAME: VALUE'` y `--header='NAME: VALUE'`.

> Los valores de las cabeceras pasados en la línea de comandos pueden quedar guardados en el historial de la shell o ser visibles para otros procesos locales. Tenlo en cuenta al pasar tokens y otros secretos.

### Ejemplo de salida (tabla)

```
--------------------------------------------------------------------------
 №      | URL de la página        | URL comprobada            | Código HTTP
--------------------------------------------------------------------------
     1. | https://example.com     | https://example.com/page1  |   200
     2. | https://example.com     | https://example.com/page2  |   404
     3. | https://example.com     | https://example.com/page3  |   200
--------------------------------------------------------------------------
```

Los códigos HTTP de la tabla se colorean según el rango:
- **2xx** — verde;
- **3xx** — amarillo;
- **4xx/5xx** — rojo.

## Casos de uso típicos de la utilidad

### 1. Comprobación de enlaces rotos en tu sitio tras un rediseño o migración

Después de cambiar el diseño, la estructura de las URL o trasladarse a un nuevo dominio, debes asegurarte de que en las páginas no queden enlaces a secciones antiguas (eliminadas) o a archivos.

```sh
check_links --fail https://mi-sitio.es/pagina/
```

La utilidad mostrará solo los enlaces que conducen a páginas inexistentes (404, 410) o a errores de servidor (500).

### 2. Auditoría SEO: búsqueda de enlaces a recursos externos que dejaron de funcionar

Los enlaces externos rotos perjudican los factores de comportamiento y la confianza de los buscadores en tu sitio. Comprobar regularmente los enlaces externos es una parte obligatoria del mantenimiento SEO.

```sh
check_links --export broken-links.csv https://mi-sitio.es/
```

El archivo CSV se puede abrir en Excel/Google Sheets y entregárselo al gestor de contenidos para su corrección.

### 3. Comprobación de enlaces en un artículo o landing antes de su publicación

Antes de publicar un material con muchas fuentes externas, conviene asegurarse de que todos los enlaces funcionan y no conducen a un 404.

```sh
check_links https://blog.mi-sitio.es/borrador-articulo/
```

Códigos verdes 200 — todo correcto, amarillos 3xx — redirecciones (conviene actualizar los enlaces a los actuales), rojos 4xx/5xx — enlaces rotos.

### 4. Supervisión de enlaces en la documentación o en una base de conocimientos

Para sitios con mucha documentación (wikis, bases de conocimientos, manuales), es útil configurar una comprobación periódica de enlaces para que la documentación esté siempre actualizada.

```sh
# Comprobación semanal mediante cron
0 6 * * 1 /usr/local/bin/check_links --fail --export /var/log/links-check/docs-errors.csv https://docs.company.ru/
```

### 5. Comprobación de enlaces en la página de un producto de una tienda online

En las fichas de los productos suele haber enlaces a productos relacionados, categorías y reseñas. Si esos enlaces no llevan a ninguna parte, son pérdidas directas de ventas.

```sh
check_links --fail https://tienda.mi-sitio.es/catalogo/producto-123/
```

### 6. Auditoría de la masa de enlaces antes de comprar enlaces

Al hacer SEO, antes de comprar enlaces a un sitio donante, conviene comprobar si tiene páginas rotas que puedan reducir el efecto de la compra.

```sh
check_links --fail https://sitio-donante.mi-sitio.es/
```

### 7. Búsqueda de imágenes que no se cargan

La utilidad recopila no solo enlaces (`<a href>`), sino también imágenes (`<img src>`). Esto permite encontrar imágenes rotas en una página, una causa frecuente del deterioro de la percepción visual del sitio.

```sh
check_links --fail https://mi-sitio.es/galeria/
```

### 8. Comprobación de redirecciones (cadenas de redirección)

Aunque la utilidad no sigue las cadenas de redirección paso a paso, muestra el código HTTP 3xx para las URL que redirigen. Esto ayuda a detectar redirecciones intermedias innecesarias que ralentizan la carga de la página.

```sh
check_links https://example.com/
```

Presta atención a las filas amarillas: son URL que devuelven 301, 302, etc.

### 9. Exportación del mapa completo de enlaces de la página para un análisis posterior

La exportación a CSV permite pasar los resultados a sistemas BI, Google Sheets o Excel para elaborar informes y paneles.

```sh
check_links --export full-links-report.csv https://mi-sitio.es/
```

### 10. Comprobación rápida del sitio de un cliente antes de una presentación

Para agencias y autónomos: antes de mostrar un sitio a un cliente, conviene pasar la página principal y las páginas típicas por la utilidad para evitar una situación incómoda con enlaces rotos durante la demo.

```sh
check_links --fail https://sitio-del-cliente.mi-sitio.es/
```

## Estructura del proyecto

| Módulo | Función |
| --- | --- |
| [`src/main.zig`](src/main.zig) | Punto de entrada CLI: análisis de argumentos (incluido el tiempo de espera, el número de solicitudes paralelas y el subcomando `completion`), así como el manejo explícito de errores con mensajes localizados y códigos de retorno correctos. |
| [`src/i18n.zig`](src/i18n.zig) | Catálogo tipado de mensajes localizados (`ru`/`en`/`es`/`fr`) y selección de la localización activa mediante `-Dlocale`. |
| [`src/lang.zig`](src/lang.zig) | Enumeración de los idiomas de interfaz admitidos (utilizada por la compilación). |
| [`src/check_links_by_page.zig`](src/check_links_by_page.zig) | Orquestación de la comprobación de enlaces en una página. |
| [`src/collect_urls.zig`](src/collect_urls.zig) | Carga de la página y recopilación de URL del HTML. |
| [`src/html_parser.zig`](src/html_parser.zig) | Analizador HTML (basado en la biblioteca `zigquery`) para extraer `href`/`src`. |
| [`src/url_normalize.zig`](src/url_normalize.zig) | Normalización y construcción de URL absolutas. |
| [`src/check_link_list.zig`](src/check_link_list.zig) | Comprobación por lotes de la lista de URL (chunks) y agrupación por código. |
| [`src/check_http.zig`](src/check_http.zig) | Comprobación concurrente de códigos HTTP. |
| [`src/http_head_client.zig`](src/http_head_client.zig) | Cliente HTTP HEAD propio con TLS y tiempo de espera. |
| [`src/request_headers.zig`](src/request_headers.zig) | Análisis de cabeceras HTTP personalizadas y política de mismo origen. |
| [`src/table_view.zig`](src/table_view.zig) | Muestra de los resultados como una tabla en la terminal. |
| [`src/export_csv.zig`](src/export_csv.zig) | Exportación de resultados a CSV. |
| [`src/TableFormatter.zig`](src/TableFormatter.zig) | Formato de la tabla según el ancho de la terminal. |
| [`src/bar.zig`](src/bar.zig) | Barra de progreso del proceso de comprobación. |
| [`src/tests.zig`](src/tests.zig) | Archivo raíz de pruebas. |
| [`src/http_integration_test.zig`](src/http_integration_test.zig) | Pruebas de integración HTTP en un servidor local. |

## Cómo funciona

1. La utilidad carga el contenido HTML de la página desde la URL indicada.
2. El analizador HTML extrae todas las URL de los atributos `href` y `src`.
3. Los enlaces relativos se normalizan a absolutos; se eliminan los duplicados.
4. Cada URL se comprueba con el método `HEAD` de forma concurrente; para la comprobación se utiliza un cliente HTTP HEAD propio con tiempo de espera de la solicitud.
5. Los resultados se agrupan por código de respuesta HTTP y se muestran en forma de tabla o archivo CSV.

## Formato CSV

Al exportar se utiliza el delimitador `;`. Estructura del archivo:

```
№;URL de la página;URL comprobada;Código HTTP
1;https://example.com;https://example.com/page1;200
2;https://example.com;https://example.com/page2;404
```

Si el archivo ya existe, antes de sobrescribirlo se renombra a `<nombre>.bak`.

## Pruebas

Ejecución de todas las pruebas:

```sh
zig build test
```

Las pruebas cubren: análisis de HTML (basado en `zigquery`), normalización de URL, recopilación de enlaces de una página, análisis de cabeceras HTTP personalizadas y política de mismo origen, comprobación de códigos HTTP en un servidor de pruebas local (incluidos los tiempos de espera y las redirecciones), formato de la tabla y exportación a CSV.

## Licencia

El proyecto se distribuye bajo la licencia **Vaslex Free Software License (versión 2.0, fechada el 11 de marzo de 2025)**. El texto completo de la licencia está disponible en el archivo [`LICENSE`](LICENSE).