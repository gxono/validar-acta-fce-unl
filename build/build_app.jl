using PackageCompiler

const RAIZ = joinpath(@__DIR__, "..")
const CARPETA_APP = joinpath(RAIZ, "build", "ValidarActaApp")

create_app(RAIZ, CARPETA_APP;
    executables = ["validar_acta" => "julia_main"],
    force = true,
    incremental = false)

println("Listo. Ejecutable en: $(joinpath(CARPETA_APP, "bin", "validar_acta.exe"))")
println("Copiá tu carpeta \"documentos\" junto al ejecutable (en $(joinpath(CARPETA_APP, "bin"))) antes de correrlo.")
