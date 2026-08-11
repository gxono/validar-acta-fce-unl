include(joinpath(@__DIR__, "src", "ValidarActa.jl"))
using .ValidarActa

INCIDENCIAS = ValidarActa.ejecutar_validacion(joinpath(@__DIR__, "documentos"))
