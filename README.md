# validar-acta-fce-unl

Herramienta en Julia para cruzar las notas que figuran en las **actas de examen en PDF**
contra las notas que los docentes tienen cargadas en una **planilla Excel**, y reportar
cualquier discrepancia (legajos faltantes, notas que no coinciden, ausentes con nota
cargada por error, etc.).

## Guía rápida: cómo descargar y usar el programa

No hace falta instalar nada ni saber programar. Estos pasos son para **Windows**.

### Paso 1: Descargar el programa

1. Entrá a esta página: [Releases](../../releases).
2. Ahí arriba de todo vas a ver la versión más reciente.
3. Un poco más abajo, esa página tiene una lista que dice **"Assets"**. Hacé clic en
   el archivo que termina en `.zip` (algo como
   `validar_acta-v0.1.2-windows-x64.zip`). Se va a descargar a tu computadora
   (normalmente termina en la carpeta "Descargas").

### Paso 2: Descomprimir el archivo descargado

1. Andá a la carpeta donde se descargó (por lo general, "Descargas").
2. Hacé **clic derecho** sobre el archivo `.zip` que bajaste.
3. En el menú que aparece, elegí **"Extraer todo..."**.
4. Elegí una carpeta donde guardarlo (por ejemplo, el Escritorio) y confirmá.

Esto va a crear una carpeta llamada `ValidarActaApp`. Adentro hay otra carpeta
llamada `bin`, y adentro de esa está el programa: un archivo llamado
`validar_acta.exe`, acompañado de varios archivos más con terminación `.dll`.

> **Importante:** no muevas ni borres ningún archivo de adentro de la carpeta `bin`
> por separado. El programa necesita que todos esos archivos estén juntos para
> funcionar. Si en algún momento querés cambiar el programa de lugar, movés la
> carpeta `ValidarActaApp` **entera**, no solo el `.exe`.

### Paso 3: Poner las actas y las planillas de notas

1. Entrá a la carpeta `ValidarActaApp` → `bin`.
2. Hacé **doble clic** en `validar_acta.exe` para abrirlo por primera vez.
3. Se va a abrir una ventana con fondo negro y letras blancas. Es normal, ahí es
   donde el programa te va a ir contando qué está haciendo. Como todavía no hay
   nada para validar, el programa va a crear solo una carpeta nueva llamada
   `documentos` en ese mismo lugar, y te va a avisar con un mensaje parecido a este:

   ```
   No encontré la carpeta "documentos" junto al programa, así que la creé.
   Poné ahí las actas (PDF) y la(s) planilla(s) de notas (Excel), y volvé a ejecutar el programa.
   ```

4. Apretá la tecla **Enter** para cerrar esa ventana.
5. Ahora, al lado de `validar_acta.exe`, va a haber una carpeta nueva llamada
   `documentos`. Entrá a esa carpeta.
6. Copiá y pegá ahí adentro:
   - Las **actas** en PDF que querés validar (los archivos que terminan en `.pdf`).
   - La planilla (o planillas) de **notas** en Excel que querés comparar contra esas
     actas (los archivos que terminan en `.xlsx`). Esa planilla tiene que cumplir:
     - Tener, como mínimo, una columna que diga "legajo" y otra que diga "nota". No
       importa si están en mayúsculas, minúsculas, ni en qué orden aparecen.
     - El encabezado ("legajo", "nota", etc.) tiene que estar en la **primera fila**
       de la hoja, sin ningún título ni fila vacía arriba.
     - No puede haber **filas en blanco** entre los datos (por ejemplo, una fila
       vacía "separadora" entre el encabezado y el primer estudiante). Si hay una,
       la hoja se va a leer incompleta o vacía, sin avisar.

No hace falta ordenar nada en subcarpetas ni ponerle nombres especiales a los
archivos: el programa distingue solo cuáles son actas y cuáles son planillas, por la
terminación del nombre del archivo (`.pdf` o `.xlsx`).

#### Ejemplos de encabezados válidos e inválidos

**Válido:** "legajo" y "nota" en la primera fila, nada más.

| legajo | nota |
|---|---|
| 44312 | 8 |
| 45123 | 6 |

**También válido:** no importan las mayúsculas, el orden, ni que haya columnas de
más (acá hay columnas que la herramienta ni siquiera mira).

| Nombre | Legajo | Email | Nota |
|---|---|---|---|
| Pérez, Ana | 44312 | ana@mail.com | 8 |
| Gómez, Luis | 45123 | luis@mail.com | 6 |

**Inválido:** el encabezado no está en la primera fila (hay un título arriba).

| Listado de notas - Materia X | |
|---|---|
| legajo | nota |
| 44312 | 8 |

**Inválido:** hay una fila en blanco en el medio de los datos.

| legajo | nota |
|---|---|
| 44312 | 8 |
| *(fila vacía)* | |
| 45123 | 6 |

### Paso 4: Validar

1. Volvé a hacer doble clic en `validar_acta.exe`.
2. Se abre de nuevo la ventana negra. Ahí vas a ver, en este orden:
   - Un resumen de qué archivos encontró: cuántas actas leyó, cuántas páginas tenía
     cada una, y cuántos estudiantes sacó de cada planilla. Sirve para confirmar de
     un vistazo que no se le pasó por alto ningún archivo.
   - La lista de problemas que encontró al comparar las actas con las planillas (por
     ejemplo, un estudiante que está en el acta pero no en la planilla, o una nota
     que no coincide). Más abajo, en [Qué hace](#qué-hace), está el detalle de qué
     significa cada tipo de problema. Si no encuentra ningún problema, te lo va a
     decir también.
3. Leé con calma el resultado (si es muy largo, podés desplazarte hacia arriba con la
   rueda del mouse o la barra de scroll de la ventana).
4. Cuando termines de leerlo, apretá **Enter** para cerrar la ventana.

### Paso 5: Repetir cada vez que haga falta

Podés correr el programa las veces que quieras. Si agregás una planilla nueva,
corregís un archivo, o sumás más actas dentro de la carpeta `documentos`, simplemente
volvé a hacer doble clic en `validar_acta.exe` y va a validar todo de nuevo con lo
que haya en ese momento.

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

---

Lo que sigue de acá para abajo **no hace falta leerlo para usar el programa**. Es
solo para quien quiera meterse en el código, correrlo desde Julia en vez del
ejecutable, o compilar su propia versión del `.exe`.

## Requisitos para compilarlo vos mismo

Estos requisitos **no aplican si solo vas a usar el programa ya compilado** (la guía
del principio de este documento). Son necesarios únicamente si vas a modificar el
código fuente o generar tu propia versión del ejecutable desde cero.

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
junto al ejecutable, en `build/ValidarActaApp/bin/documentos/`. La app siempre busca
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

MIT. Ver [LICENSE](LICENSE).
