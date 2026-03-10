import XCTest
@testable import Tasks

/// Tests para verificar que la extracción de sprint solo identifica sprints legítimos.
/// Simula el parsing de respuestas de Jira con diferentes estructuras de customfields.
final class SprintExtractionTests: XCTestCase {

    // MARK: - Tests de prioridad de estado

    func testSprintPriority_activeHasHighestPriority() {
        XCTAssertGreaterThan(sprintStatePriority("active"), sprintStatePriority("future"))
        XCTAssertGreaterThan(sprintStatePriority("active"), sprintStatePriority("closed"))
    }
    
    func testSprintPriority_futureHigherThanClosed() {
        XCTAssertGreaterThan(sprintStatePriority("future"), sprintStatePriority("closed"))
    }
    
    func testSprintPriority_closedHigherThanUnknown() {
        XCTAssertGreaterThan(sprintStatePriority("closed"), sprintStatePriority("unknown"))
        XCTAssertGreaterThan(sprintStatePriority("closed"), sprintStatePriority(nil))
    }

    // MARK: - Tests de validación de objetos sprint

    func testIsSprintObject_validSprintWithState_returnsTrue() {
        let sprint: [String: Any] = [
            "id": 123,
            "name": "Sprint 1",
            "state": "active"
        ]
        XCTAssertTrue(isSprintObject(sprint), "Sprint válido con state debe ser reconocido")
    }
    
    func testIsSprintObject_validSprintWithSelfUrl_returnsTrue() {
        let sprint: [String: Any] = [
            "id": 456,
            "name": "Sprint 2",
            "self": "https://test.atlassian.net/rest/agile/1.0/sprint/456"
        ]
        XCTAssertTrue(isSprintObject(sprint), "Sprint válido con self URL debe ser reconocido")
    }
    
    func testIsSprintObject_missingId_returnsFalse() {
        let invalid: [String: Any] = [
            "name": "Not a sprint",
            "state": "active"
        ]
        XCTAssertFalse(isSprintObject(invalid), "Objeto sin id no es sprint")
    }
    
    func testIsSprintObject_missingName_returnsFalse() {
        let invalid: [String: Any] = [
            "id": 123,
            "state": "active"
        ]
        XCTAssertFalse(isSprintObject(invalid), "Objeto sin name no es sprint")
    }
    
    func testIsSprintObject_missingStateAndSelf_returnsFalse() {
        let invalid: [String: Any] = [
            "id": 123,
            "name": "Fake sprint"
        ]
        XCTAssertFalse(isSprintObject(invalid), "Objeto sin state ni self no es sprint")
    }
    
    func testIsSprintObject_idNotInt_returnsFalse() {
        let invalid: [String: Any] = [
            "id": "123",  // String en lugar de Int
            "name": "Sprint 1",
            "state": "active"
        ]
        XCTAssertFalse(isSprintObject(invalid), "Sprint con id no numérico no es válido")
    }

    // MARK: - Tests de campos falsos comunes

    func testIsSprintObject_teamField_returnsFalse() {
        let teamField: [String: Any] = [
            "name": "Team Alpha",
            "description": "Engineering team"
        ]
        XCTAssertFalse(isSprintObject(teamField), "Campo de team no debe ser reconocido como sprint")
    }
    
    func testIsSprintObject_componentField_returnsFalse() {
        let component: [String: Any] = [
            "name": "Backend",
            "description": "Backend components"
        ]
        XCTAssertFalse(isSprintObject(component), "Campo de componente no debe ser reconocido como sprint")
    }
    
    func testIsSprintObject_projectField_returnsFalse() {
        let project: [String: Any] = [
            "name": "Project XYZ",
            "key": "PROJ"
        ]
        XCTAssertFalse(isSprintObject(project), "Campo de proyecto no debe ser reconocido como sprint")
    }

    // MARK: - Tests de mejor sprint en array

    func testBestSprintName_prefersActiveOverClosed() {
        let sprints: [[String: Any]] = [
            ["id": 1, "name": "Sprint Cerrado", "state": "closed"],
            ["id": 2, "name": "Sprint Activo", "state": "active"]
        ]
        
        let result = bestSprintName(from: sprints)
        XCTAssertEqual(result, "Sprint Activo", "Debe priorizar sprint activo")
    }
    
    func testBestSprintName_prefersFutureOverClosed() {
        let sprints: [[String: Any]] = [
            ["id": 1, "name": "Sprint Cerrado", "state": "closed"],
            ["id": 2, "name": "Sprint Futuro", "state": "future"]
        ]
        
        let result = bestSprintName(from: sprints)
        XCTAssertEqual(result, "Sprint Futuro", "Debe priorizar sprint futuro sobre cerrado")
    }
    
    func testBestSprintName_prefersActiveOverFuture() {
        let sprints: [[String: Any]] = [
            ["id": 1, "name": "Sprint Futuro", "state": "future"],
            ["id": 2, "name": "Sprint Activo", "state": "active"]
        ]
        
        let result = bestSprintName(from: sprints)
        XCTAssertEqual(result, "Sprint Activo", "Debe priorizar sprint activo sobre futuro")
    }
    
    func testBestSprintName_emptyArray_returnsNil() {
        let result = bestSprintName(from: [])
        XCTAssertNil(result, "Array vacío debe devolver nil")
    }
    
    func testBestSprintName_invalidObjects_returnsNil() {
        let invalid: [[String: Any]] = [
            ["name": "Not a sprint", "description": "fake"],
            ["id": "wrong", "name": "Also fake"]
        ]
        
        let result = bestSprintName(from: invalid)
        XCTAssertNil(result, "Array sin sprints válidos debe devolver nil")
    }
    
    func testBestSprintName_mixedValidAndInvalid_returnsValidSprint() {
        let mixed: [[String: Any]] = [
            ["name": "Fake team", "description": "not a sprint"],
            ["id": 789, "name": "Real Sprint", "state": "active"],
            ["id": "wrong", "name": "Also fake"]
        ]
        
        let result = bestSprintName(from: mixed)
        XCTAssertEqual(result, "Real Sprint", "Debe extraer solo el sprint válido")
    }

    func testBestSprintName_onlyClosedSprint_returnsNil() {
        let closedOnly: [[String: Any]] = [
            ["id": 1, "name": "Sprint Cerrado", "state": "closed"]
        ]
        let result = bestSprintName(from: closedOnly)
        XCTAssertNil(result, "Un sprint que ya pasó no debe mostrarse como seleccionado")
    }

    // MARK: - Test helpers (duplican la lógica privada de JiraProvider)

    private func isSprintObject(_ obj: [String: Any]) -> Bool {
        guard let _ = obj["id"] as? Int,
              let _ = obj["name"] as? String else {
            return false
        }
        return obj["state"] != nil || obj["self"] != nil
    }
    
    private func sprintStatePriority(_ state: String?) -> Int {
        switch (state ?? "").lowercased() {
        case "active": return 3
        case "future": return 2
        case "closed": return 1
        default: return 0
        }
    }
    
    private func bestSprintName(from arr: [[String: Any]]) -> String? {
        let validSprints = arr.filter { isSprintObject($0) }
        guard !validSprints.isEmpty else { return nil }
        
        let best = validSprints.compactMap { item -> (name: String, priority: Int)? in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let state = item["state"] as? String
            return (name, sprintStatePriority(state))
        }.max(by: { $0.priority < $1.priority })
        guard let b = best, b.priority > 1 else { return nil }
        return b.name
    }
}
