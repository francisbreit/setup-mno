(function initializeAssistantRouteMetadata(global) {
  "use strict";

  const specialists = Object.freeze({
    security_reviewer: "Revisor de segurança",
    troubleshooting_specialist: "Especialista em troubleshooting",
    capacity_planner: "Planejador de capacidade",
    blueprint_architect: "Arquiteto de Blueprints",
    integration_architect: "Arquiteto de integrações",
    setup_specialist: "Especialista em setups",
    infrastructure_diagnostician: "Diagnóstico de infraestrutura",
    scope_guard: "Guardião de escopo"
  });
  const risks = Object.freeze({ low: "baixo", medium: "médio", high: "alto" });
  const semver = /^\d+\.\d+\.\d+$/;

  function specialistLabel(value) {
    return specialists[value] || "Especialista não identificado";
  }

  function riskLabel(value) {
    return risks[value] || "não informado";
  }

  function snapshot(route) {
    if (!route || typeof route !== "object") return null;
    const specialist = String(route.specialist || "");
    const specialistName = specialistLabel(specialist);
    const risk = String(route.riskLevel || "");
    const promptVersion = String(route.promptVersion || "");
    const responseContractVersion = String(route.responseContractVersion || "");
    if (specialistName === "Especialista não identificado" || !risks[risk] ||
        !semver.test(promptVersion) || !semver.test(responseContractVersion)) return null;
    return Object.freeze({
      specialist,
      specialistName,
      risk,
      riskName: riskLabel(risk),
      promptVersion,
      responseContractVersion
    });
  }

  global.SetupMNOAssistantRoute = Object.freeze({ snapshot, specialistLabel, riskLabel });
})(globalThis);
