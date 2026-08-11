module ValidarActa

using PDFIO, DataFrames, XLSX

export ejecutar_validacion, julia_main


# --- Parche a PDFIO para que funcione en un ejecutable compilado con PackageCompiler ---
#
# `PDFIO.PD.read_afm` ubica sus archivos de métricas de fuente (.afm) con una ruta
# calculada con `@__DIR__` en tiempo de compilación (ver PDFontMetrics.jl de PDFIO).
# Al compilar esta app con PackageCompiler, esa ruta queda fija al `.julia` de la
# máquina donde se compiló y no existe en la máquina donde corre el ejecutable, lo
# que rompe la extracción de texto con un `SystemError: ...Helvetica.afm`.
# Como workaround, embebemos una copia de esos archivos (en `pdfio_fonts/`, vendored
# desde PDFIO) como datos leídos en tiempo de compilación (no como rutas), y
# reemplazamos `read_afm` para que los use en vez de leer del disco.
#
# El reemplazo se hace con `eval` sobre el módulo `PDFIO.PD`, algo que Julia prohíbe
# durante la PRECOMPILACIÓN de un paquete ("Evaluation into the closed module ...
# breaks incremental compilation"), que es justo lo que hace PackageCompiler al
# generar el sysimage. Por eso el parche no se aplica al cargar este módulo, sino
# recién en tiempo de ejecución real, la primera vez que se llama a
# `ejecutar_validacion` (ver `_parchear_pdfio_afm` más abajo).
const _RUTA_FUENTES_AFM = joinpath(@__DIR__, "pdfio_fonts")

const _DATOS_AFM = Dict{String,String}(
    splitext(archivo)[1] => read(joinpath(_RUTA_FUENTES_AFM, archivo), String)
    for archivo in readdir(_RUTA_FUENTES_AFM) if endswith(archivo, ".afm"))

const _PDFIO_PARCHEADO = Ref(false)

function _parchear_pdfio_afm()
    _PDFIO_PARCHEADO[] && return
    _PDFIO_PARCHEADO[] = true

    Core.eval(PDFIO.PD, quote
        function read_afm(fontname::AbstractString)
            d_name_w = Dict{CosName,Int}()
            d_cid_w = Dict{Int,Int}()
            lines = collect(eachline(IOBuffer($_DATOS_AFM[fontname])))
            bStartCharMetrics = false
            bReadKernPairs = false
            nMetrics = 0
            nLineRead = 0
            afm = AdobeFontMetrics()
            next = iterate(lines)
            while next !== nothing
                (line, state) = next
                if startswith(line, "ItalicAngle")
                    v = split(line)
                    afm.italicAngle = parse(Float32, v[2])
                elseif startswith(line, "IsFixedPitch")
                    v = split(line)
                    afm.isFixedPitch = parse(Bool, v[2])
                elseif startswith(line, "FontName")
                    v = split(line)
                    afm.fontname = CosName(v[2])
                elseif startswith(line, "Weight")
                    v = split(line)
                    afm.weight = Symbol(v[2])
                else
                    bStartCharMetrics = startswith(line, "StartCharMetrics")
                    bReadKernPairs = startswith(line, "StartKernPairs")
                    if bStartCharMetrics || bReadKernPairs
                        v = split(line)
                        n = parse(Int, v[2])
                        if bStartCharMetrics
                            populate_char_metrics(lines, state, afm, n)
                            bStartCharMetrics = false
                        end
                        if bReadKernPairs
                            populate_kern_pairs(lines, state, afm, n)
                            bReadKernPairs = false
                        end
                    end
                end
                next = iterate(lines, state)
            end
            return afm
        end
    end)
end


const PATRON_LINEA_ESTUDIANTE = r"""
    ^\s*
    (?<n>\d{1,2})\s+
    (?<legajo>[\w\d\-]+\d)\s*
    (?<nombre>[\w\s,´'\-]+)\s{2,}
    (?<documento>.*)\s*
    (?<fecha>\d{2}/\d{2}/\d{4})\s*
    (?<condicion>[\w\s])\s{2}
    (?:
        (?<ausente>Ausente)
        |
        (?<nota>\d{1,2})\s
        \((?<nota_texto>\w+)\)\s
        (?<calificacion>\S.*\S|\S)
    )
    \s*$
"""x

const PATRON_LINEA_FRECUENCIAS = r"""
    Insc\.\sAus\.\sExam\.\sSobres\.\s\(10\)\sDistinguido\s\(9\)Muy\sBueno\s\(8\)\sBueno\s\(7\)\sAprobado\s\(6\)\sInsuficiente\s\(1\-2\-3\-4\-5\)\s+Total\s(?:Parcial|Final)\s*
    (?<parcial_inscripto>\d+)\s*
    (?<parcial_ausente>\d+)\s*
    (?<parcial_presente>\d+)\s*
    (?<parcial_sobresaliente>\d+)\s*
    (?<parcial_distinguido>\d+)\s*
    (?<parcial_muy_bueno>\d+)\s*
    (?<parcial_bueno>\d+)\s*
    (?<parcial_aprobado>\d+)\s*
    (?<parcial_insuficiente>\d+)\s*
    (?<parcial_total>\d+)
    """x

const PATRON_NUMERO_ACTA = r"Acta de Exámenes Número:\s*(?<nacta>\S+)\s+"

const PATRON_FACULTAD = r"Facultad:\s*(?<facultad>[\w\s]+)\s{2,}"

const PATRON_CARRERA = r"Carrera:\s*(?<carrera>[\w\s]+?)(?:ES\sCOPIA|\s{2,})"


function _error_captura_estudiantes_cantidad_diferente(df, m, page, file)
    if isnothing(m)
        @warn "No se encontró pie de página en la página $page del archivo \"$file\" para poder validar la cantidad de estudiantes de la página. Por favor, revise manualmente si el acta es válida o comuníquese con jperren."
    elseif nrow(df) != parse(Int, m[:parcial_inscripto])
        error("No coincide la cantidad de estudiantes capturados ($(nrow(df))) con los detallados en el pie de página ($(m[:parcial_inscripto])) en la página $page del archivo \"$file\"")
    end
end


function _error_captura_resumen_pie(m, page, file)
    if isnothing(m)
        @warn "No se pudo capturar el pie de página en la página $page del archivo \"$file\"."
    end
end


function _tabla_vacia()
    DataFrame(
        :acta_archivo => String[],
        :facultad => String[],
        :acta_numero => String[],
        :acta_npagina => Int[],
        :acta_nfila => Int[],
        :legajo => String[],
        :nombre => String[],
        :carrera => String[],
        :documento => String[],
        :fecha => String[],
        :presente => Bool[],
        :condicion => String[],
        :nota => Union{Int64,Missing}[],
        :nota_texto => Union{String,Missing}[],
        :calificacion => Union{String,Missing}[])
end


function _procesar_pdf(tabla_vacia, buffer, carpeta_actas, nombre_pdf)
    estudiantes_total = similar(tabla_vacia, 0)
    npages = 0

    doc = pdDocOpen(joinpath(carpeta_actas, nombre_pdf))
    try
        npages = pdDocGetPageCount(doc)

        for npage in 1:npages
            estudiantes_parcial = similar(tabla_vacia, 0)

            page = pdDocGetPage(doc, npage)
            pdPageExtractText(buffer, page)

            texto = String(take!(buffer))

            m = match(PATRON_NUMERO_ACTA, texto)
            isnothing(m) ? error("No se encontró número de acta ($(nombre_pdf): pag $npage)") : (acta_numero = m[:nacta])
            m = match(PATRON_FACULTAD, texto)
            isnothing(m) ? error("No se encontró nombre de facultad ($(nombre_pdf): pag $npage)") : (facultad = m[:facultad])
            m = match(PATRON_CARRERA, texto)
            isnothing(m) ? error("No se encontró carrera ($(nombre_pdf): pag $npage)") : (carrera = m[:carrera])

            resumen_frecuencia_pie = match(PATRON_LINEA_FRECUENCIAS, texto)
            _error_captura_resumen_pie(resumen_frecuencia_pie, npage, nombre_pdf)

            for linea in split(texto, "\n")
                linea_estudiante = match(PATRON_LINEA_ESTUDIANTE, linea)
                if !isnothing(linea_estudiante)

                    # Diferenciar si estudiante estuvo ausente o no.
                    if !isnothing(linea_estudiante[:ausente])
                        nota = missing
                        nota_texto = missing
                        calificacion = missing
                        presente = false
                    else
                        nota = parse(Int64, linea_estudiante[:nota])
                        nota_texto = linea_estudiante[:nota_texto]
                        calificacion = linea_estudiante[:calificacion]
                        presente = true
                    end

                    push!(estudiantes_parcial, (;
                        facultad, acta_numero, carrera,
                        acta_nfila = parse(Int, linea_estudiante[:n]),
                        acta_npagina = npage,
                        acta_archivo = nombre_pdf,
                        legajo = linea_estudiante[:legajo],
                        nombre = linea_estudiante[:nombre],
                        documento = linea_estudiante[:documento],
                        fecha = linea_estudiante[:fecha],
                        condicion = linea_estudiante[:condicion],
                        presente, nota, nota_texto, calificacion))
                end
            end

            _error_captura_estudiantes_cantidad_diferente(estudiantes_parcial, resumen_frecuencia_pie, npage, nombre_pdf)

            estudiantes_total = vcat(estudiantes_total, estudiantes_parcial)
        end
    finally
        pdDocClose(doc)
    end

    return estudiantes_total, npages
end


"""
Lee todos los PDF de `carpeta_actas`. Devuelve una tupla `(estudiantes, resumen)`,
donde `resumen` tiene una fila por acta con la cantidad de páginas y de
estudiantes capturados, para poder verificar de un vistazo que se leyó todo.
"""
function procesar_actas(carpeta_actas::AbstractString)
    lista_pdf = filter(f -> endswith(lowercase(f), ".pdf"), readdir(carpeta_actas))

    resumen = DataFrame(archivo = String[], paginas = Int[], estudiantes = Int[])

    if isempty(lista_pdf)
        println("No se encontraron archivos PDF en \"$carpeta_actas\".")
        return _tabla_vacia(), resumen
    end

    buffer = IOBuffer()
    tabla_vacia = _tabla_vacia()
    tabla_estudiantes = _tabla_vacia()

    for nombre_pdf in lista_pdf
        estudiantes_total, paginas = _procesar_pdf(tabla_vacia, buffer, carpeta_actas, nombre_pdf)
        tabla_estudiantes = vcat(tabla_estudiantes, estudiantes_total)
        push!(resumen, (archivo = nombre_pdf, paginas = paginas, estudiantes = nrow(estudiantes_total)))
        println("Listo $nombre_pdf")
    end

    return tabla_estudiantes, resumen
end


"""
Imprime el resumen de lectura de actas (PDF): cuántas páginas y estudiantes se
capturaron por archivo, para poder chequear a simple vista que ninguna quedó afuera.
"""
function imprimir_resumen_actas(resumen::AbstractDataFrame)
    println()
    println("=== Actas leídas (PDF) ===")
    if isempty(resumen)
        println("No se encontraron archivos PDF.")
        return
    end

    for r in eachrow(resumen)
        println("- $(r.archivo): $(r.paginas) página(s), $(r.estudiantes) estudiante(s) capturado(s)")
    end
    println("Total: $(nrow(resumen)) acta(s), $(sum(resumen.estudiantes)) estudiante(s) capturado(s).")
end


"""
Lee todas las hojas de todos los `.xlsx` de `directorio`. Devuelve una tupla
`(estudiantes, resumen)`, donde `resumen` tiene una fila por cada hoja de cada
libro, indicando si se incluyó (tenía columnas "legajo" y "nota") o no y por qué.
"""
function procesar_xlsx(directorio::AbstractString)
    todos_archivos = readdir(directorio)
    archivos = filter(contains(r"^[^~].*\.xlsx$"i), todos_archivos)

    # Archivos que parecen planillas de Excel pero en un formato que no leemos
    # (solo soportamos .xlsx): avisar en vez de ignorarlos en silencio.
    for archivo in filter(contains(r"^[^~].*\.(xls|xlsm)$"i), todos_archivos)
        @warn "El archivo \"$archivo\" no se puede leer (solo se soporta .xlsx). Convertilo a .xlsx y volvé a intentar."
    end

    tablas = DataFrame[]
    resumen = DataFrame(archivo = String[], hoja = String[], incluida = Bool[], estudiantes = Int[], motivo = String[])

    for archivo in archivos
        ruta = joinpath(directorio, archivo)
        nombres_hojas = XLSX.openxlsx(xf -> XLSX.sheetnames(xf), ruta)

        for nombre_hoja in nombres_hojas
            tabla = XLSX.readto(ruta, nombre_hoja, DataFrame)
            tabla = rename(col -> lowercase(strip(string(col))), tabla)

            if !all(in(propertynames(tabla)), (:legajo, :nota))
                push!(resumen, (; archivo, hoja = nombre_hoja, incluida = false, estudiantes = 0,
                    motivo = "no tiene columnas \"legajo\" y \"nota\" (columnas encontradas: $(join(names(tabla), ", ")))"))
                continue
            end

            # La fila 1 es el encabezado, así que la fila de Excel de cada dato es su índice + 1.
            tabla.hoja_fila = axes(tabla, 1) .+ 1

            tabla = select(tabla, :legajo, :nota, :hoja_fila)

            # Excel suele "extender" el rango de la hoja más allá de los datos reales:
            # descartamos filas en blanco (sin legajo) para no tratarlas como estudiantes.
            tabla = tabla[.!ismissing.(tabla.legajo) .& (strip.(string.(tabla.legajo)) .!= ""), :]

            tabla.hoja_archivo .= archivo
            tabla.hoja_nombre .= nombre_hoja
            push!(tablas, tabla)
            push!(resumen, (; archivo, hoja = nombre_hoja, incluida = true, estudiantes = nrow(tabla), motivo = ""))
        end
    end

    tabla_vacia = DataFrame(
        legajo = String[], nota = Union{Missing,Int64}[], hoja_fila = Int[],
        hoja_archivo = String[], hoja_nombre = String[])
    datos = isempty(tablas) ? tabla_vacia : reduce((a, b) -> vcat(a, b, cols = :union), tablas)
    return datos, resumen
end


"""
Imprime el resumen de lectura de hojas de notas (Excel): por cada libro, cuántas
hojas tiene, cuáles se incluyeron (tenían "legajo" y "nota") y cuántos estudiantes
aportó cada una, para poder chequear a simple vista que no quedó ninguna afuera
por error.
"""
function imprimir_resumen_hojas(resumen::AbstractDataFrame)
    println()
    println("=== Hojas de notas leídas (Excel) ===")
    if isempty(resumen)
        println("No se encontraron archivos Excel.")
        return
    end

    for grupo in groupby(resumen, :archivo)
        incluidas = grupo[grupo.incluida, :]
        println("- $(grupo.archivo[1]): $(nrow(grupo)) hoja(s), $(nrow(incluidas)) incluida(s), $(sum(incluidas.estudiantes; init = 0)) estudiante(s)")
        for r in eachrow(grupo)
            if r.incluida
                println("    · \"$(r.hoja)\": $(r.estudiantes) estudiante(s)")
            else
                println("    · \"$(r.hoja)\": omitida ($(r.motivo))")
            end
        end
    end
end


"""
Normaliza un legajo a `String` en minúsculas y sin espacios, para que el join no
falle por diferencias de tipo (Int64 vs String), mayúsculas/minúsculas, o espacios
en blanco entre el PDF y el Excel.
"""
_normalizar_legajo(legajo) = lowercase(strip(string(legajo)))


"""
Avisa si hay legajos repetidos en `df`, ya que un legajo duplicado hace que el
outerjoin genere un producto cartesiano (cada fila se cruza con todas las que
matchean) y ensucia el reporte sin avisar.
"""
function _advertir_legajos_duplicados(df::AbstractDataFrame, origen::AbstractString)
    duplicados = unique(df.legajo[nonunique(df, :legajo)])
    if !isempty(duplicados)
        @warn "Hay legajos duplicados en $origen: $(join(duplicados, ", "))"
    end
end


"""
Devuelve el primer valor no-`missing` de `row` entre las columnas de `cols` que
existan (sirve para leer, p. ej., `:nombre_acta` o `:nombre` según si la columna
quedó sufijada o no tras el join).
"""
function _primero_no_missing(row, cols)
    for c in cols
        if hasproperty(row, c)
            v = getproperty(row, c)
            ismissing(v) || return v
        end
    end
    return missing
end


"""
Recorre el resultado del outerjoin acta/hoja y arma un DataFrame con una fila
por cada incidencia detectada:
- `falta_en_acta` / `falta_en_hoja`: el legajo no aparece de un lado.
- `ausente_con_nota_en_hoja`: el acta marca al estudiante ausente pero la hoja
  tiene un valor numérico cargado (no se asume cuál está mal, solo se avisa).
- `falta_nota_en_hoja`: el estudiante rindió (según el acta) pero la hoja no
  tiene nota cargada.
- `nota_no_coincide`: ambas fuentes tienen nota pero difieren.
"""
function detectar_incidencias(df::AbstractDataFrame, legajos_acta::Set, legajos_hoja::Set)
    incidencias = DataFrame(
        legajo = String[], nombre = Union{Missing,String}[],
        problema = String[], detalle = String[],
        nota_acta = Union{Missing,Int64}[], nota_hoja = Any[],
        acta_archivo = Union{Missing,String}[], acta_npagina = Union{Missing,Int}[], acta_nfila = Union{Missing,Int}[],
        hoja_archivo = Union{Missing,String}[], hoja_nombre = Union{Missing,String}[], hoja_fila = Union{Missing,Int}[])

    for r in eachrow(df)
        en_acta = r.legajo in legajos_acta
        en_hoja = r.legajo in legajos_hoja

        nombre = _primero_no_missing(r, (:nombre_acta, :nombre, :nombre_hoja))
        nota_acta = _primero_no_missing(r, (:nota_acta, :nota))
        nota_hoja = hasproperty(r, :nota_hoja) ? r.nota_hoja : (hasproperty(r, :nota) ? r.nota : missing)
        acta_archivo = _primero_no_missing(r, (:acta_archivo_acta, :acta_archivo))
        acta_npagina = _primero_no_missing(r, (:acta_npagina_acta, :acta_npagina))
        acta_nfila = _primero_no_missing(r, (:acta_nfila_acta, :acta_nfila))
        hoja_archivo = hasproperty(r, :hoja_archivo) ? r.hoja_archivo : missing
        hoja_nombre = hasproperty(r, :hoja_nombre) ? r.hoja_nombre : missing
        hoja_fila = hasproperty(r, :hoja_fila) ? r.hoja_fila : missing
        presente = _primero_no_missing(r, (:presente_acta, :presente))

        problema, detalle = if !en_acta
            "falta_en_acta", "El legajo está en la hoja de notas pero no aparece en ningún acta."
        elseif !en_hoja
            "falta_en_hoja", "El legajo está en el acta pero no aparece en la hoja de notas."
        elseif presente === false
            if !ismissing(nota_hoja)
                "ausente_con_nota_en_hoja", "El acta marca al estudiante como AUSENTE, pero la hoja tiene cargado un valor ($nota_hoja). Revisar manualmente."
            else
                continue
            end
        elseif ismissing(nota_hoja)
            "falta_nota_en_hoja", "El acta tiene nota ($nota_acta) pero la hoja no tiene nada cargado."
        elseif !isequal(nota_acta, nota_hoja)
            "nota_no_coincide", "Nota en acta ($nota_acta) distinta a la nota en hoja ($nota_hoja)."
        else
            continue
        end

        push!(incidencias, (; legajo = r.legajo, nombre, problema, detalle,
            nota_acta, nota_hoja, acta_archivo, acta_npagina, acta_nfila, hoja_archivo, hoja_nombre, hoja_fila))
    end

    return incidencias
end


"""
Imprime `incidencias` en la consola, agrupadas por tipo de problema, con el
detalle necesario para revisar cada caso manualmente.
"""
function imprimir_incidencias(incidencias::AbstractDataFrame)
    if isempty(incidencias)
        @info "No se detectaron incidencias: legajos y notas coinciden entre actas y hoja(s)."
        return
    end

    for grupo in groupby(incidencias, :problema)
        println()
        println("=== $(nrow(grupo)) incidencia(s) de tipo \"$(grupo.problema[1])\" ===")
        for r in eachrow(grupo)
            println("-"^60)
            println("Legajo: $(r.legajo)")
            ismissing(r.nombre) || println("Nombre: $(r.nombre)")
            println(r.detalle)
            ismissing(r.acta_archivo) || println("Acta: $(r.acta_archivo) (página $(r.acta_npagina), fila $(r.acta_nfila))")
            ismissing(r.hoja_archivo) || println("Libro: $(r.hoja_archivo), hoja \"$(r.hoja_nombre)\" (fila $(r.hoja_fila))")
        end
    end
    println("-"^60)
    println("Total de incidencias: $(nrow(incidencias))")
end


"""
Corre el proceso completo de validación sobre `carpeta`: lee actas y hojas de
notas, imprime sus resúmenes de lectura, las cruza por legajo y reporta las
incidencias encontradas. Devuelve el DataFrame de incidencias.
"""
function ejecutar_validacion(carpeta::AbstractString)
    if !isdir(carpeta)
        error("No existe la carpeta \"$carpeta\".")
    end

    _parchear_pdfio_afm()

    datos_actas, resumen_actas = procesar_actas(carpeta)
    imprimir_resumen_actas(resumen_actas)

    datos_hoja, resumen_hojas = procesar_xlsx(carpeta)
    imprimir_resumen_hojas(resumen_hojas)

    transform!(datos_actas, :legajo => ByRow(_normalizar_legajo) => :legajo)
    transform!(datos_hoja, :legajo => ByRow(_normalizar_legajo) => :legajo)

    _advertir_legajos_duplicados(datos_actas, "las actas")
    _advertir_legajos_duplicados(datos_hoja, "la(s) hoja(s) de notas")

    legajos_acta = Set(datos_actas.legajo)
    legajos_hoja = Set(datos_hoja.legajo)

    base_completa = outerjoin(datos_actas, datos_hoja, on = :legajo, renamecols = "_acta" => "_hoja")

    incidencias = detectar_incidencias(base_completa, legajos_acta, legajos_hoja)
    imprimir_incidencias(incidencias)

    return incidencias
end


"""
Punto de entrada para el ejecutable compilado con PackageCompiler. Busca una
carpeta "documentos" junto al ejecutable (o en el directorio actual si se corre
desde el REPL) y corre la validación sobre ella.
"""
function julia_main()::Cint
    carpeta = joinpath(dirname(Base.PROGRAM_FILE), "documentos")
    isdir(carpeta) || (carpeta = joinpath(pwd(), "documentos"))

    codigo = 0
    try
        if !isdir(carpeta)
            mkpath(carpeta)
            println("No encontré la carpeta \"documentos\" junto al programa, así que la creé.")
            println("Poné ahí las actas (PDF) y la(s) planilla(s) de notas (Excel), y volvé a ejecutar el programa.")
        else
            ejecutar_validacion(carpeta)
        end
    catch e
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        codigo = 1
    end

    # Sin esto, al abrir el .exe con doble clic en Windows la consola se cierra
    # apenas termina y no da tiempo a leer el resultado.
    println()
    print("Presione Enter para salir...")
    readline()

    return codigo
end

end # module
