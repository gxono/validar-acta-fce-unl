module ValidarActa

using PDFIO, DataFrames, XLSX

export ejecutar_validacion, julia_main


# PDFIO.PD.read_afm ubica sus .afm con una ruta absoluta calculada en tiempo de
# compilación, que queda rota en un ejecutable compilado (SystemError:
# ...Helvetica.afm). Acá los embebemos como datos y reemplazamos read_afm para que
# los use. El reemplazo (eval sobre PDFIO.PD) no puede hacerse al cargar este
# módulo porque Julia lo prohíbe durante la precompilación de un paquete; por eso
# se aplica recién en tiempo de ejecución, la primera vez que se llama a
# ejecutar_validacion.
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
    (?:.*)\s*
    (?:\d{2}/\d{2}/\d{4})\s*
    (?:[\w\s])\s{2}
    (?:
        (?<ausente>Ausente)
        |
        (?<nota>\d{1,2})\s
        \((?:\w+)\)\s
        (?:\S.*\S|\S)
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
        :acta_npagina => Int[],
        :acta_nfila => Int[],
        :legajo => String[],
        :nombre => String[],
        :presente => Bool[],
        :nota => Union{Int64,Missing}[])
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

            # Algunas actas traen una "Hoja de firmas" al final (sin estudiantes):
            # se cuenta como página del PDF pero no se procesa como si tuviera datos.
            if occursin(r"hoja\s+de\s+firmas"i, texto)
                continue
            end

            resumen_frecuencia_pie = match(PATRON_LINEA_FRECUENCIAS, texto)
            _error_captura_resumen_pie(resumen_frecuencia_pie, npage, nombre_pdf)

            for linea in split(texto, "\n")
                linea_estudiante = match(PATRON_LINEA_ESTUDIANTE, linea)
                if !isnothing(linea_estudiante)
                    if !isnothing(linea_estudiante[:ausente])
                        nota = missing
                        presente = false
                    else
                        nota = parse(Int64, linea_estudiante[:nota])
                        presente = true
                    end

                    push!(estudiantes_parcial, (;
                        acta_nfila = parse(Int, linea_estudiante[:n]),
                        acta_npagina = npage,
                        acta_archivo = nombre_pdf,
                        legajo = linea_estudiante[:legajo],
                        nombre = linea_estudiante[:nombre],
                        presente, nota))
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
    end

    return tabla_estudiantes, resumen
end


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


function procesar_xlsx(directorio::AbstractString)
    todos_archivos = readdir(directorio)
    archivos = filter(contains(r"^[^~].*\.xlsx$"i), todos_archivos)

    for archivo in filter(contains(r"^[^~].*\.(xls|xlsm)$"i), todos_archivos)
        @warn "El archivo \"$archivo\" no se puede leer (solo se soporta .xlsx). Convertilo a .xlsx y volvé a intentar."
    end

    tablas = DataFrame[]
    resumen = DataFrame(archivo = String[], hoja = String[], incluida = Bool[], estudiantes = Int[], motivo = String[])

    for archivo in archivos
        ruta = joinpath(directorio, archivo)

        for nombre_hoja in XLSX.openxlsx(xf -> XLSX.sheetnames(xf), ruta)
            # Sin rango de columnas explícito, XLSX.jl corta en la primera celda de
            # encabezado vacía; "A:CZ" evita ese corte. El encabezado tiene que estar
            # en la fila 1 y sin filas en blanco entre los datos (XLSX.jl corta ahí también).
            tabla = XLSX.readto(ruta, nombre_hoja, "A:CZ", DataFrame)
            tabla = rename(col -> lowercase(strip(string(col))), tabla)

            if !all(in(propertynames(tabla)), (:legajo, :nota))
                columnas_reales = filter(c -> !startswith(c, "#empty"), lowercase.(names(tabla)))
                push!(resumen, (; archivo, hoja = nombre_hoja, incluida = false, estudiantes = 0,
                    motivo = join(columnas_reales, ", ")))
                continue
            end

            tabla.hoja_fila = axes(tabla, 1) .+ 1
            tabla = select(tabla, :legajo, :nota, :hoja_fila)
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
                println("    · \"$(r.hoja)\": omitida, no tiene columnas \"legajo\" y \"nota\"")
                println("        columnas encontradas: $(r.motivo)")
            end
        end
    end
end


# Legajos numéricos a veces quedan cargados en Excel como número (44312.0) en vez
# de texto; sin el chequeo de Int, string(44312.0) da "44312.0" y no empareja con
# el "44312" del acta.
function _normalizar_legajo(legajo)
    if legajo isa AbstractFloat && isinteger(legajo)
        return lowercase(strip(string(Int(legajo))))
    end
    return lowercase(strip(string(legajo)))
end


# Un legajo duplicado hace que el outerjoin genere un producto cartesiano.
function _advertir_legajos_duplicados(df::AbstractDataFrame, origen::AbstractString)
    duplicados = unique(df.legajo[nonunique(df, :legajo)])
    if !isempty(duplicados)
        @warn "Hay legajos duplicados en $origen: $(join(duplicados, ", "))"
    end
end


# El outerjoin sufija con "_acta"/"_hoja" TODAS las columnas de cada lado (no solo
# las que chocan de nombre), así que hay que probar ambas formas.
function _primero_no_missing(row, cols)
    for c in cols
        if hasproperty(row, c)
            v = getproperty(row, c)
            ismissing(v) || return v
        end
    end
    return missing
end


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
        hoja_archivo = _primero_no_missing(r, (:hoja_archivo_hoja, :hoja_archivo))
        hoja_nombre = _primero_no_missing(r, (:hoja_nombre_hoja, :hoja_nombre))
        hoja_fila = _primero_no_missing(r, (:hoja_fila_hoja, :hoja_fila))
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


function imprimir_incidencias(incidencias::AbstractDataFrame)
    if isempty(incidencias)
        @info "No se detectaron incidencias: legajos y notas coinciden entre actas y hoja(s)."
        return
    end

    for grupo in groupby(incidencias, :problema)
        println()
        println("="^60)
        println("$(nrow(grupo)) incidencia(s) de tipo \"$(grupo.problema[1])\"")
        println("="^60)
        for (i, r) in enumerate(eachrow(grupo))
            i == 1 || println("-"^60)
            println("Legajo: $(r.legajo)")
            ismissing(r.nombre) || println("Nombre: $(r.nombre)")
            println(r.detalle)
            ismissing(r.acta_archivo) || println("Acta: $(r.acta_archivo) (página $(r.acta_npagina), fila $(r.acta_nfila))")
            ismissing(r.hoja_archivo) || println("Libro: $(r.hoja_archivo), hoja \"$(r.hoja_nombre)\" (fila $(r.hoja_fila))")
        end
    end
    println("="^60)
    println("Total de incidencias: $(nrow(incidencias))")
end


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

    println()
    print("Presione Enter para salir...")
    readline()

    return codigo
end

end # module
