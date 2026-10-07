import Foundation

/// Detectores con lógica propia (versiones sin usar, modelos huérfanos…): cada grupo vive en su propio archivo
/// (`Detectores+Grupo.swift`) y devuelve elementos de cualquier categoría. Se ejecutan una sola vez por análisis.
extension Escaner {
    func detectados(_ categoria: Categoria, _ c: Contexto) -> [Elemento] {
        if c.memoria.detectados == nil {
            c.memoria.detectados = todosLosDetectores(c)
        }
        return (c.memoria.detectados ?? []).filter { $0.categoria == categoria }
    }

    private func todosLosDetectores(_ c: Contexto) -> [Elemento] {
        let grupos: [(Contexto) -> [Elemento]] = [
            detectoresA_HuggingFace,
            detectoresA_ModelosLocales,
        ]
        return grupos.flatMap { $0(c) }
    }
}
