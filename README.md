# validar-acta-fce-unl

Herramienta en Julia para cruzar las notas que figuran en las **actas de examen en PDF**
contra las notas que los docentes tienen cargadas en una **planilla Excel**, y reportar
cualquier discrepancia (legajos faltantes, notas que no coinciden, ausentes con nota
cargada por error, etc.).

## Qué hace

La carpeta `documentos/` tiene que tener dos tipos de archivo: las **actas oficiales**
(`.pdf`, las que se suben/firman en el sistema) y la o las **planillas de notas del
docente** (`.xlsx`, la fuente que se quiere validar contra el acta). No hace falta
separarlos en subcarpetas ni nombrarlos de una forma particular: la herramienta
distingue uno de otro por la extensión de archivo.

1. Lee todos los `.pdf` (las actas) de la carpeta `documentos/` y extrae, de cada
   acta: legajo, nombre, condición (presente/ausente) y nota de cada estudiante,
   junto con el archivo/página/fila donde aparece cada dato.
2. Lee todos los `.xlsx` (las planillas de notas del docente) de la misma carpeta.
   Revisa **todas las hojas** de cada libro y usa las que tengan columnas `legajo` y
   `nota` (sin importar mayúsculas/minúsculas ni espacios de más en el encabezado);
   el resto se ignora.
3. Cruza acta y planilla por legajo (normalizado: minúsculas y sin espacios, para que
   no fallen coincidencias por formato) y reporta las incidencias encontradas:

   | Incidencia | Significado |
   |---|---|
   | `falta_en_acta` | El legajo está en la hoja de notas pero no aparece en ningún acta. |
   | `falta_en_hoja` | El legajo está en el acta pero no aparece en la hoja de notas. |
   | `ausente_con_nota_en_hoja` | El acta marca al estudiante como ausente, pero la hoja tiene un valor numérico cargado. |
   | `falta_nota_en_hoja` | El estudiante rindió (según el acta) pero la hoja no tiene nota cargada. |
   | `nota_no_coincide` | Ambas fuentes tienen nota, pero no coinciden. |

4. Antes de cruzar, imprime en consola un resumen de lectura (páginas y estudiantes
   capturados por acta; hojas incluidas/omitidas y estudiantes por cada una), para
   detectar de entrada si algún archivo quedó afuera sin que sea evidente por qué.

## Requisitos

- [Julia](https://julialang.org/) 1.10 o superior (probado con 1.12).

## Uso interactivo (REPL / VSCode)

1. Poné los PDF y Excel a validar dentro de `documentos/`.
2. Desde la carpeta del proyecto:

   ```julia
   julia --project=. script.jl
   ```

   O, desde el REPL de Julia con la extensión de VSCode, simplemente ejecutá
   [`script.jl`](script.jl) (activa el entorno del proyecto automáticamente si tu
   carpeta de trabajo es la raíz del repo).

3. El resultado de la validación (`INCIDENCIAS`) queda disponible como `DataFrame` en
   el REPL para inspeccionarlo, además de imprimirse en consola.

## Estructura del proyecto

```
.
├── Project.toml / Manifest.toml   Dependencias del paquete (DataFrames, PDFIO, XLSX)
├── script.jl                      Lanzador para uso interactivo (REPL/VSCode)
├── src/
│   ├── ValidarActa.jl             Toda la lógica, como módulo Julia
│   └── pdfio_fonts/                Copia de las fuentes estándar que necesita PDFIO
│                                    (ver "Nota técnica" más abajo)
├── documentos/                    Carpeta donde van los PDF y Excel a validar
└── build/
    ├── Project.toml                Entorno de compilación (PackageCompiler)
    └── build_app.jl                Script que genera el ejecutable standalone
```

## Compilar como ejecutable standalone

El proyecto está preparado para compilarse con
[PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) y así generar un
`.exe` que no requiere tener Julia instalado.

```
cd build
julia --project=. build_app.jl
```

La primera compilación tarda bastante (compilación del sysimage; puede llevar entre
10 y 30 minutos según la máquina). Al terminar, deja el ejecutable en:

```
build/ValidarActaApp/bin/validar_acta.exe
```

Antes de correrlo, copiá la carpeta `documentos/` (con los PDF y Excel a validar)
junto al ejecutable, en `build/ValidarActaApp/bin/documentos/` — la app siempre busca
una carpeta con ese nombre al lado suyo.

### Nota técnica: por qué existe `src/pdfio_fonts/`

`PDFIO.jl` (la librería que lee los PDF) ubica sus archivos de métricas de fuente
(`Helvetica.afm` y similares) con una ruta absoluta calculada en tiempo de
compilación, fija al `.julia` de la máquina donde se compiló. Al empaquetar la app
con PackageCompiler, esa ruta no existe en la máquina donde corre el ejecutable, y la
extracción de texto falla con un `SystemError: ...Helvetica.afm`.

Como workaround, `src/ValidarActa.jl` vendorea una copia de esos archivos (en
`src/pdfio_fonts/`), los embebe como datos en tiempo de compilación (no como rutas), y
reemplaza `PDFIO.PD.read_afm` para que los use en lugar de leer del disco. El parche se
aplica en tiempo de ejecución real (no al cargar el módulo), porque Julia prohíbe hacer
`eval` sobre un módulo ajeno durante la precompilación de un paquete.

## Licencia

MIT — ver [LICENSE](LICENSE).
