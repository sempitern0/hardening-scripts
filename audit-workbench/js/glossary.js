/* Diccionario técnico offline para auditorías. Contenido orientativo, no certifica cumplimiento. */
'use strict';
(() => {
 const TERMS=Object.freeze([
  {
    "id": "term-1",
    "title": "Segmentación de red",
    "category": "Redes",
    "description": "Separar equipos y servicios en zonas con reglas de comunicación explícitas.",
    "check": "Identifica VLAN/subredes, revisa ACL y firewall entre zonas y prueba solamente flujos autorizados."
  },
  {
    "id": "term-2",
    "title": "VLAN",
    "category": "Redes",
    "description": "Red lógica de capa 2 identificada habitualmente con una etiqueta IEEE 802.1Q.",
    "check": "Comprueba puertos de acceso/trunk, VLAN nativa y políticas inter-VLAN."
  },
  {
    "id": "term-3",
    "title": "CIDR",
    "category": "Redes",
    "description": "Notación que expresa dirección de red y longitud del prefijo, por ejemplo 192.168.10.0/24.",
    "check": "Valida solapamientos y comprueba si las rutas permiten el tráfico esperado."
  },
  {
    "id": "term-4",
    "title": "DMZ",
    "category": "Redes",
    "description": "Zona separada para servicios expuestos, limitada respecto a redes internas.",
    "check": "Comprueba que un servidor de DMZ no puede alcanzar libremente sistemas de gestión."
  },
  {
    "id": "term-5",
    "title": "MFA",
    "category": "Identidad",
    "description": "Autenticación con dos o más factores de distinta naturaleza.",
    "check": "Verifica cobertura de administradores, recuperación segura y excepciones autorizadas."
  },
  {
    "id": "term-6",
    "title": "Principio de mínimo privilegio",
    "category": "Identidad",
    "description": "Otorgar solo los permisos necesarios durante el tiempo necesario.",
    "check": "Revisa membresías privilegiadas, accesos de servicio y revisiones periódicas."
  },
  {
    "id": "term-7",
    "title": "CVE",
    "category": "Vulnerabilidades",
    "description": "Identificador público de una vulnerabilidad; no demuestra por sí solo que un activo sea vulnerable.",
    "check": "Confirma producto, versión, configuración, exposición y evidencia de afectación."
  },
  {
    "id": "term-8",
    "title": "CVSS",
    "category": "Vulnerabilidades",
    "description": "Sistema de puntuación de características técnicas de vulnerabilidades.",
    "check": "No lo uses como única medida de riesgo; considera exposición y criticidad del activo."
  },
  {
    "id": "term-9",
    "title": "EOL / Fin de vida",
    "category": "Sistemas",
    "description": "Fin de un ciclo de vida definido por el fabricante, distinto según versión y contrato.",
    "check": "Consulta la política oficial de soporte del producto y registra su fecha."
  },
  {
    "id": "term-10",
    "title": "EDR",
    "category": "Sistemas",
    "description": "Tecnología de detección y respuesta sobre endpoints.",
    "check": "Comprueba cobertura, política aplicada, telemetría y capacidad de reacción."
  },
  {
    "id": "term-11",
    "title": "Hardening",
    "category": "Sistemas",
    "description": "Reducción de superficie de ataque mediante configuración segura.",
    "check": "Contrasta la configuración efectiva con una referencia apropiada y documenta excepciones."
  },
  {
    "id": "term-12",
    "title": "RPO",
    "category": "Continuidad",
    "description": "Pérdida máxima de datos tolerada, expresada como intervalo temporal.",
    "check": "Contrasta RPO acordado con frecuencia y resultados de copias."
  },
  {
    "id": "term-13",
    "title": "RTO",
    "category": "Continuidad",
    "description": "Tiempo objetivo para recuperar un servicio después de una interrupción.",
    "check": "Comprueba con pruebas de restauración y dependencias reales."
  },
  {
    "id": "term-14",
    "title": "Regla de firewall",
    "category": "Redes",
    "description": "Política que permite o deniega tráfico según origen, destino, puerto, protocolo y contexto.",
    "check": "Revisa reglas amplias, caducidad, registro y justificación de negocio."
  },
  {
    "id": "term-15",
    "title": "Evidencia SHA-256",
    "category": "Evidencias",
    "description": "Huella criptográfica para comparar la integridad de un archivo concreto.",
    "check": "Conserva el archivo original y calcula nuevamente la huella al verificarlo."
  },
  {
    "id": "term-16",
    "title": "Riesgo residual",
    "category": "Riesgos",
    "description": "Riesgo que permanece tras aplicar medidas y controles compensatorios.",
    "check": "Registra aceptación responsable y fecha de revisión; no equivale a corrección."
  },
  {
    "id": "term-17",
    "title": "Criticidad del activo",
    "category": "Riesgos",
    "description": "Importancia de un activo para los procesos y datos de negocio.",
    "check": "Considera confidencialidad, integridad, disponibilidad y dependencias."
  },
  {
    "id": "term-18",
    "title": "NAT",
    "category": "Redes",
    "description": "Traducción de direcciones de red; no sustituye un control de acceso.",
    "check": "Revisa reglas de publicación y relación con filtrado de firewall."
  },
  {
    "id": "term-19",
    "title": "VPN",
    "category": "Redes",
    "description": "Canal protegido entre extremos o redes sobre un transporte no confiable.",
    "check": "Comprueba autenticación, algoritmos, segmentación y revocación."
  },
  {
    "id": "term-20",
    "title": "Cadena de custodia",
    "category": "Evidencias",
    "description": "Registro documentado de obtención, almacenamiento, acceso y transferencias de evidencias.",
    "check": "Registra origen, fecha, responsable, hash y ubicación protegida."
  }
]);
 const clean=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 const search=q=>TERMS.filter(t=>clean([t.title,t.category,t.description,t.check].join(' ')).includes(clean(q)));
 globalThis.AuditGlossary=Object.freeze({TERMS,search});
})();
