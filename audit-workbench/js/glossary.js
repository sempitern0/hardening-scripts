/* Diccionario técnico offline · orientativo, sin diagnóstico automático. */
'use strict';
(() => {
 const TERMS=Object.freeze([
  {
    "id": "term-1",
    "title": "Segmentación de red",
    "category": "Redes",
    "description": "Una red segmentada separa equipos y servicios en zonas con reglas de comunicación explícitas.",
    "check": "Identifica VLAN/subredes, revisa ACL y firewall entre zonas y prueba solamente flujos autorizados.",
    "why": "Limita comunicaciones innecesarias y dificulta el movimiento lateral.",
    "aliases": [
      "red segmentada",
      "segmentar red",
      "aislamiento de red"
    ],
    "example": "Ejemplo: una VLAN de invitados no puede iniciar conexiones a la red de servidores."
  },
  {
    "id": "term-2",
    "title": "VLAN",
    "category": "Redes",
    "description": "Red lógica de capa 2 identificada habitualmente con una etiqueta IEEE 802.1Q.",
    "check": "Comprueba puertos de acceso/trunk, VLAN nativa y políticas inter-VLAN.",
    "why": "Una VLAN por sí sola no garantiza aislamiento: deben existir reglas inter-VLAN.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-3",
    "title": "CIDR",
    "category": "Redes",
    "description": "Notación que expresa dirección de red y longitud del prefijo, por ejemplo 192.168.10.0/24.",
    "check": "Valida solapamientos y comprueba si las rutas permiten el tráfico esperado.",
    "why": "Un prefijo mal definido puede ampliar el alcance o provocar solapamientos.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-4",
    "title": "DMZ",
    "category": "Redes",
    "description": "Zona separada para servicios expuestos, limitada respecto a redes internas.",
    "check": "Comprueba que un servidor de DMZ no puede alcanzar libremente sistemas de gestión.",
    "why": "Separa servicios expuestos de activos internos sensibles.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-5",
    "title": "MFA",
    "category": "Identidad",
    "description": "Autenticación con dos o más factores de distinta naturaleza.",
    "check": "Verifica cobertura de administradores, recuperación segura y excepciones autorizadas.",
    "why": "Reduce accesos indebidos cuando una contraseña se ve comprometida.",
    "aliases": [
      "2FA",
      "doble factor",
      "autenticación multifactor"
    ],
    "example": ""
  },
  {
    "id": "term-6",
    "title": "Principio de mínimo privilegio",
    "category": "Identidad",
    "description": "Otorgar solo los permisos necesarios durante el tiempo necesario.",
    "check": "Revisa membresías privilegiadas, accesos de servicio y revisiones periódicas.",
    "why": "Disminuye las consecuencias de una cuenta comprometida.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-7",
    "title": "CVE",
    "category": "Vulnerabilidades",
    "description": "Identificador público de una vulnerabilidad; no demuestra por sí solo que un activo sea vulnerable.",
    "check": "Confirma producto, versión, configuración, exposición y evidencia de afectación.",
    "why": "Distingue una referencia publicada de una afectación realmente demostrada.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-8",
    "title": "CVSS",
    "category": "Vulnerabilidades",
    "description": "Sistema de puntuación de características técnicas de vulnerabilidades.",
    "check": "No lo uses como única medida de riesgo; considera exposición y criticidad del activo.",
    "why": "Una puntuación técnica no sustituye la evaluación de riesgo de negocio.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-9",
    "title": "EOL / Fin de vida",
    "category": "Sistemas",
    "description": "Fin de un ciclo de vida definido por el fabricante, distinto según versión y contrato.",
    "check": "Consulta la política oficial de soporte del producto y registra su fecha.",
    "why": "Los productos sin soporte pueden dejar de recibir correcciones.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-10",
    "title": "EDR",
    "category": "Sistemas",
    "description": "Tecnología de detección y respuesta sobre endpoints.",
    "check": "Comprueba cobertura, política aplicada, telemetría y capacidad de reacción.",
    "why": "Permite detectar comportamientos sospechosos y apoyar la respuesta.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-11",
    "title": "Hardening",
    "category": "Sistemas",
    "description": "Reducción de superficie de ataque mediante configuración segura.",
    "check": "Contrasta la configuración efectiva con una referencia apropiada y documenta excepciones.",
    "why": "Reduce servicios, permisos y configuraciones innecesarias.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-12",
    "title": "RPO",
    "category": "Continuidad",
    "description": "Pérdida máxima de datos tolerada, expresada como intervalo temporal.",
    "check": "Contrasta RPO acordado con frecuencia y resultados de copias.",
    "why": "Ayuda a determinar cuántos datos puede tolerar perder el negocio.",
    "aliases": [],
    "example": "Ejemplo: un RPO de 4 horas permite perder hasta cuatro horas de cambios."
  },
  {
    "id": "term-13",
    "title": "RTO",
    "category": "Continuidad",
    "description": "Tiempo objetivo para recuperar un servicio después de una interrupción.",
    "check": "Comprueba con pruebas de restauración y dependencias reales.",
    "why": "Ayuda a planificar cuándo debe volver a operar un servicio.",
    "aliases": [],
    "example": "Ejemplo: un RTO de 2 horas fija la recuperación objetivo del servicio."
  },
  {
    "id": "term-14",
    "title": "Regla de firewall",
    "category": "Redes",
    "description": "Política que permite o deniega tráfico según origen, destino, puerto, protocolo y contexto.",
    "check": "Revisa reglas amplias, caducidad, registro y justificación de negocio.",
    "why": "Los permisos amplios permiten comunicaciones que quizá no sean necesarias.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-15",
    "title": "Evidencia SHA-256",
    "category": "Evidencias",
    "description": "Huella criptográfica para comparar la integridad de un archivo concreto.",
    "check": "Conserva el archivo original y calcula nuevamente la huella al verificarlo.",
    "why": "Permite comprobar alteraciones posteriores del archivo original.",
    "aliases": [
      "hash",
      "sha256"
    ],
    "example": ""
  },
  {
    "id": "term-16",
    "title": "Riesgo residual",
    "category": "Riesgos",
    "description": "Riesgo que permanece tras aplicar medidas y controles compensatorios.",
    "check": "Registra aceptación responsable y fecha de revisión; no equivale a corrección.",
    "why": "Mantiene visibles las amenazas que siguen existiendo tras las medidas.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-17",
    "title": "Criticidad del activo",
    "category": "Riesgos",
    "description": "Importancia de un activo para los procesos y datos de negocio.",
    "check": "Considera confidencialidad, integridad, disponibilidad y dependencias.",
    "why": "Permite priorizar según procesos e información realmente importantes.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-18",
    "title": "NAT",
    "category": "Redes",
    "description": "Traducción de direcciones de red; no sustituye un control de acceso.",
    "check": "Revisa reglas de publicación y relación con filtrado de firewall.",
    "why": "Una traducción de direcciones no implica que el acceso esté restringido.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-19",
    "title": "VPN",
    "category": "Redes",
    "description": "Canal protegido entre extremos o redes sobre un transporte no confiable.",
    "check": "Comprueba autenticación, algoritmos, segmentación y revocación.",
    "why": "Protege tránsito, pero necesita autenticación y acceso delimitado.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-20",
    "title": "Cadena de custodia",
    "category": "Evidencias",
    "description": "Registro documentado de obtención, almacenamiento, acceso y transferencias de evidencias.",
    "check": "Registra origen, fecha, responsable, hash y ubicación protegida.",
    "why": "Apoya la trazabilidad e integridad de los materiales recopilados.",
    "aliases": [],
    "example": ""
  },
  {
    "id": "term-21",
    "title": "Subred",
    "category": "Redes",
    "description": "División lógica de una red IP que define qué direcciones pertenecen al mismo segmento.",
    "check": "Confirma el prefijo, la máscara, el gateway y la ausencia de solapamientos.",
    "why": "Una subred demasiado amplia aumenta la exposición lateral.",
    "aliases": [
      "subnet",
      "máscara de red"
    ],
    "example": ""
  },
  {
    "id": "term-22",
    "title": "ACL",
    "category": "Redes",
    "description": "Lista de reglas para permitir o denegar tráfico o acciones según condiciones definidas.",
    "check": "Revisa orden, destino, origen, excepciones y registros de las reglas.",
    "why": "Un permiso excesivo puede abrir acceso entre segmentos.",
    "aliases": [
      "lista de control de acceso"
    ],
    "example": ""
  },
  {
    "id": "term-23",
    "title": "Microsegmentación",
    "category": "Redes",
    "description": "Aplicación de políticas de comunicación granulares entre cargas, equipos o servicios.",
    "check": "Comprueba reglas entre aplicaciones y denegación por defecto cuando corresponda.",
    "why": "Reduce el movimiento lateral después de comprometer un equipo.",
    "aliases": [
      "microsegmentacion"
    ],
    "example": ""
  },
  {
    "id": "term-24",
    "title": "802.1X / NAC",
    "category": "Redes",
    "description": "Control de acceso a red que autentica dispositivos o usuarios antes de autorizar conectividad.",
    "check": "Valida autenticación, perfiles de invitados y puertos excepcionados.",
    "why": "Ayuda a limitar equipos no autorizados en la red.",
    "aliases": [
      "network access control",
      "control de acceso a red"
    ],
    "example": ""
  },
  {
    "id": "term-25",
    "title": "DNS",
    "category": "Redes",
    "description": "Servicio que transforma nombres de dominio en información como direcciones IP.",
    "check": "Comprueba resolutores, registros, zonas, transferencias y resolución interna.",
    "why": "Una configuración incorrecta facilita desvíos o interrupciones.",
    "aliases": [
      "domain name system"
    ],
    "example": ""
  },
  {
    "id": "term-26",
    "title": "DHCP",
    "category": "Redes",
    "description": "Protocolo que asigna automáticamente configuración IP a los equipos.",
    "check": "Verifica rangos, reservas, opciones críticas y servidores autorizados.",
    "why": "Un servidor DHCP no autorizado puede desviar tráfico.",
    "aliases": [
      "asignación automática IP"
    ],
    "example": ""
  },
  {
    "id": "term-27",
    "title": "ARP Spoofing",
    "category": "Redes",
    "description": "Suplantación de respuestas ARP para alterar la asociación entre una IP y una MAC.",
    "check": "Revisa protecciones de capa 2 y evidencia de anomalías de ARP.",
    "why": "Puede facilitar interceptación o interrupción dentro de una LAN.",
    "aliases": [
      "ARP poisoning"
    ],
    "example": ""
  },
  {
    "id": "term-28",
    "title": "Puertos de administración",
    "category": "Redes",
    "description": "Servicios destinados a configurar y operar equipos, como SSH, RDP o paneles web.",
    "check": "Comprueba exposición, MFA, restricciones por IP y trazabilidad de accesos.",
    "why": "Su exposición innecesaria aumenta la superficie de ataque.",
    "aliases": [
      "SSH",
      "RDP",
      "gestión remota"
    ],
    "example": ""
  },
  {
    "id": "term-29",
    "title": "TLS",
    "category": "Redes",
    "description": "Protocolo criptográfico para proteger comunicaciones de red.",
    "check": "Comprueba certificado, versión negociada, cifrados y validación del extremo.",
    "why": "Protege confidencialidad e integridad en tránsito.",
    "aliases": [
      "transport layer security",
      "SSL"
    ],
    "example": ""
  },
  {
    "id": "term-30",
    "title": "Certificado digital",
    "category": "Redes",
    "description": "Documento firmado que vincula una clave pública con una identidad o servicio.",
    "check": "Revisa identidad, emisor, validez, algoritmo y renovación.",
    "why": "Errores de confianza pueden permitir suplantaciones o fallos de servicio.",
    "aliases": [
      "certificado TLS",
      "PKI"
    ],
    "example": ""
  },
  {
    "id": "term-31",
    "title": "WPA2 / WPA3",
    "category": "Redes",
    "description": "Mecanismos de seguridad para autenticar y proteger redes Wi-Fi.",
    "check": "Comprueba modo empresarial/personal, credenciales y aislamiento de invitados.",
    "why": "Reduce accesos inalámbricos no autorizados.",
    "aliases": [
      "wifi",
      "wifi seguro"
    ],
    "example": ""
  },
  {
    "id": "term-32",
    "title": "Red de invitados",
    "category": "Redes",
    "description": "Segmento aislado para dispositivos que no deben acceder a recursos corporativos.",
    "check": "Prueba el aislamiento respecto a servidores, administración y otras VLAN.",
    "why": "Un invitado no debe acceder por defecto a datos internos.",
    "aliases": [
      "guest wifi",
      "Wi-Fi invitados"
    ],
    "example": ""
  },
  {
    "id": "term-33",
    "title": "Zero Trust",
    "category": "Redes",
    "description": "Enfoque de acceso que no presupone confianza por ubicación de red.",
    "check": "Verifica identidad, dispositivo, contexto y controles de acceso por recurso.",
    "why": "Evita confiar automáticamente en quien está conectado a la LAN.",
    "aliases": [
      "confianza cero",
      "ztna"
    ],
    "example": ""
  },
  {
    "id": "term-34",
    "title": "Parches de seguridad",
    "category": "Sistemas",
    "description": "Actualizaciones que corrigen fallos conocidos de software o firmware.",
    "check": "Contrasta inventario, versiones instaladas, ventanas y excepciones.",
    "why": "Los fallos sin corregir pueden permitir explotación conocida.",
    "aliases": [
      "patch management",
      "gestión de parches"
    ],
    "example": ""
  },
  {
    "id": "term-35",
    "title": "CIS Benchmark",
    "category": "Sistemas",
    "description": "Guía de configuraciones técnicas recomendadas para productos concretos.",
    "check": "Registra perfil, versión de referencia, desviaciones y excepciones.",
    "why": "Ayuda a establecer una línea base reproducible; no certifica cumplimiento.",
    "aliases": [
      "cis benchmarks"
    ],
    "example": ""
  },
  {
    "id": "term-36",
    "title": "Servicio expuesto",
    "category": "Sistemas",
    "description": "Proceso accesible por red que escucha conexiones en un puerto o interfaz.",
    "check": "Verifica propietario, necesidad, alcance y controles de autenticación.",
    "why": "Servicios innecesarios amplían la superficie de ataque.",
    "aliases": [
      "puerto abierto"
    ],
    "example": ""
  },
  {
    "id": "term-37",
    "title": "Firmware",
    "category": "Sistemas",
    "description": "Software integrado en el hardware que controla sus funciones internas.",
    "check": "Registra fabricante, versión, soporte y procedimiento de actualización.",
    "why": "Puede contener vulnerabilidades incluso si el SO está actualizado.",
    "aliases": [
      "BIOS",
      "UEFI"
    ],
    "example": ""
  },
  {
    "id": "term-38",
    "title": "Secure Boot",
    "category": "Sistemas",
    "description": "Mecanismo para verificar la integridad de componentes del arranque según la cadena de confianza.",
    "check": "Comprueba estado, claves, política y excepciones necesarias.",
    "why": "Dificulta arranques con componentes no autorizados.",
    "aliases": [
      "arranque seguro"
    ],
    "example": ""
  },
  {
    "id": "term-39",
    "title": "TPM",
    "category": "Sistemas",
    "description": "Componente que protege operaciones criptográficas y puede almacenar claves de forma segura.",
    "check": "Valida disponibilidad, versión y uso con cifrado o atestación.",
    "why": "Mejora la protección de claves y ciertas verificaciones de arranque.",
    "aliases": [
      "trusted platform module"
    ],
    "example": ""
  },
  {
    "id": "term-40",
    "title": "Cifrado de disco",
    "category": "Sistemas",
    "description": "Protección de información almacenada mediante claves criptográficas.",
    "check": "Comprueba cobertura, recuperación de claves y excepciones.",
    "why": "Mitiga exposición de datos ante pérdida o robo del dispositivo.",
    "aliases": [
      "bitlocker",
      "luks",
      "filevault"
    ],
    "example": ""
  },
  {
    "id": "term-41",
    "title": "Inventario de activos",
    "category": "Sistemas",
    "description": "Registro identificable de equipos y componentes bajo responsabilidad de una organización.",
    "check": "Verifica propietario, ubicación, versión, criticidad y fechas de revisión.",
    "why": "Sin inventario completo es difícil priorizar controles.",
    "aliases": [
      "asset inventory",
      "CMDB"
    ],
    "example": ""
  },
  {
    "id": "term-42",
    "title": "EPP / Antivirus",
    "category": "Sistemas",
    "description": "Protección preventiva de endpoints frente a familias de amenazas conocidas.",
    "check": "Revisa cobertura, firmas, políticas, alertas y exclusiones.",
    "why": "La instalación por sí sola no acredita protección efectiva.",
    "aliases": [
      "antivirus",
      "endpoint protection"
    ],
    "example": ""
  },
  {
    "id": "term-43",
    "title": "Virtualización",
    "category": "Sistemas",
    "description": "Ejecución de máquinas virtuales compartiendo hardware físico.",
    "check": "Revisa aislamiento, acceso al hipervisor, snapshots y actualizaciones.",
    "why": "Comprometer el plano de gestión puede afectar a muchas máquinas.",
    "aliases": [
      "hipervisor",
      "hypervisor"
    ],
    "example": ""
  },
  {
    "id": "term-44",
    "title": "SBOM",
    "category": "Sistemas",
    "description": "Inventario de componentes y dependencias de una aplicación o producto.",
    "check": "Comprueba versión, origen, actualización y relación con vulnerabilidades.",
    "why": "Facilita evaluar impacto de fallos en dependencias.",
    "aliases": [
      "software bill of materials"
    ],
    "example": ""
  },
  {
    "id": "term-45",
    "title": "Active Directory",
    "category": "Identidad",
    "description": "Servicio de directorio para identidades, grupos, equipos y políticas en entornos Windows.",
    "check": "Revisa controladores, privilegios, replicación, GPO y autenticación.",
    "why": "Una configuración débil puede comprometer el dominio completo.",
    "aliases": [
      "AD",
      "directorio activo"
    ],
    "example": ""
  },
  {
    "id": "term-46",
    "title": "GPO",
    "category": "Identidad",
    "description": "Política de grupo que distribuye configuraciones a equipos y usuarios de dominio.",
    "check": "Valida vínculo, precedencia, alcance y resultados aplicados.",
    "why": "Las configuraciones no efectivas pueden crear una falsa sensación de seguridad.",
    "aliases": [
      "group policy",
      "política de grupo"
    ],
    "example": ""
  },
  {
    "id": "term-47",
    "title": "Kerberos",
    "category": "Identidad",
    "description": "Protocolo de autenticación basado en tickets, ampliamente usado en dominios Windows.",
    "check": "Comprueba cuentas de servicio, tiempos, cifrados y configuraciones de autenticación.",
    "why": "Su mal uso o configuración facilita abuso de credenciales.",
    "aliases": [
      "ticket kerberos"
    ],
    "example": ""
  },
  {
    "id": "term-48",
    "title": "LDAP / LDAPS",
    "category": "Identidad",
    "description": "Protocolo de consulta de directorios; LDAPS utiliza protección TLS para la conexión.",
    "check": "Verifica cifrado, firmas, certificados y servicios que dependen de él.",
    "why": "Conexiones no protegidas pueden exponer consultas o autenticaciones.",
    "aliases": [
      "directorio LDAP"
    ],
    "example": ""
  },
  {
    "id": "term-49",
    "title": "Cuenta privilegiada",
    "category": "Identidad",
    "description": "Identidad con permisos elevados para administrar sistemas o datos.",
    "check": "Comprueba titular, MFA, justificación, segregación y uso real.",
    "why": "Una cuenta privilegiada comprometida tiene impacto alto.",
    "aliases": [
      "administrador",
      "privileged account"
    ],
    "example": ""
  },
  {
    "id": "term-50",
    "title": "PAM",
    "category": "Identidad",
    "description": "Gestión y supervisión de accesos privilegiados, con controles y registros específicos.",
    "check": "Revisa bóveda, aprobación, sesiones, rotación y cuentas de emergencia.",
    "why": "Reduce exposición de credenciales administrativas.",
    "aliases": [
      "privileged access management"
    ],
    "example": ""
  },
  {
    "id": "term-51",
    "title": "Cuenta de servicio",
    "category": "Identidad",
    "description": "Identidad técnica utilizada por tareas, aplicaciones o servicios.",
    "check": "Verifica permisos mínimos, custodia, rotación y prohibición de uso interactivo cuando proceda.",
    "why": "Sus contraseñas suelen quedar olvidadas durante años.",
    "aliases": [
      "service account",
      "gMSA"
    ],
    "example": ""
  },
  {
    "id": "term-52",
    "title": "SSO",
    "category": "Identidad",
    "description": "Inicio de sesión único para acceder a varios servicios con una identidad central.",
    "check": "Comprueba sesiones, MFA, proveedores y revocación.",
    "why": "Centraliza controles, pero el proveedor de identidad requiere protección especial.",
    "aliases": [
      "single sign-on"
    ],
    "example": ""
  },
  {
    "id": "term-53",
    "title": "RBAC",
    "category": "Identidad",
    "description": "Modelo de permisos basado en funciones o roles definidos.",
    "check": "Revisa asignaciones, separación de tareas y privilegios acumulados.",
    "why": "Facilita limitar permisos por necesidad operativa.",
    "aliases": [
      "role based access control"
    ],
    "example": ""
  },
  {
    "id": "term-54",
    "title": "Identidad federada",
    "category": "Identidad",
    "description": "Confianza entre proveedores de identidad para autenticar usuarios entre dominios.",
    "check": "Comprueba metadatos, confianza, expiración y reclamaciones aceptadas.",
    "why": "Configuraciones deficientes pueden permitir acceso indebido entre organizaciones.",
    "aliases": [
      "SAML",
      "OpenID Connect",
      "OIDC"
    ],
    "example": ""
  },
  {
    "id": "term-55",
    "title": "Acceso condicional",
    "category": "Identidad",
    "description": "Reglas de autenticación que consideran señales como dispositivo, riesgo o ubicación.",
    "check": "Revisa políticas, exclusiones, cobertura y cuentas de emergencia.",
    "why": "Refuerza accesos sensibles sin depender solo de contraseñas.",
    "aliases": [
      "conditional access"
    ],
    "example": ""
  },
  {
    "id": "term-56",
    "title": "CWE",
    "category": "Vulnerabilidades",
    "description": "Catálogo de clases de debilidades de software y diseño, diferente de una CVE concreta.",
    "check": "Relaciona el defecto observado con su clase y evidencia técnica.",
    "why": "Ayuda a entender la causa raíz y evitar repeticiones.",
    "aliases": [
      "common weakness enumeration"
    ],
    "example": ""
  },
  {
    "id": "term-57",
    "title": "CPE",
    "category": "Vulnerabilidades",
    "description": "Identificador estandarizado de productos y plataformas utilizado en correlación de vulnerabilidades.",
    "check": "Confirma que la versión y la variante corresponden al activo real.",
    "why": "Las coincidencias imprecisas causan falsos positivos.",
    "aliases": [
      "common platform enumeration"
    ],
    "example": ""
  },
  {
    "id": "term-58",
    "title": "EPSS",
    "category": "Vulnerabilidades",
    "description": "Estimación probabilística de que una CVE se explote durante un horizonte temporal.",
    "check": "Registra fecha y fuente de la consulta; combina con exposición y riesgo de negocio.",
    "why": "Aporta señal de priorización, no prueba explotación ni compromiso.",
    "aliases": [
      "exploit prediction scoring system"
    ],
    "example": ""
  },
  {
    "id": "term-59",
    "title": "CISA KEV",
    "category": "Vulnerabilidades",
    "description": "Catálogo de vulnerabilidades con explotación conocida mantenido por CISA.",
    "check": "Verifica si una CVE figura en el catálogo y la vigencia de la consulta.",
    "why": "Ayuda a priorizar, sin sustituir la confirmación de afectación.",
    "aliases": [
      "known exploited vulnerabilities",
      "KEV"
    ],
    "example": ""
  },
  {
    "id": "term-60",
    "title": "Falso positivo",
    "category": "Vulnerabilidades",
    "description": "Detección que parece un problema pero no se confirma en el activo.",
    "check": "Valida versión, configuración y prueba reproducible antes de informar.",
    "why": "Evita remediaciones innecesarias y pérdida de credibilidad.",
    "aliases": [
      "false positive"
    ],
    "example": ""
  },
  {
    "id": "term-61",
    "title": "Prueba de concepto (PoC)",
    "category": "Vulnerabilidades",
    "description": "Demostración controlada de que un comportamiento técnico es posible.",
    "check": "Documenta autorización, límites, evidencia y medidas para evitar impacto.",
    "why": "No toda PoC demuestra explotabilidad en el sistema evaluado.",
    "aliases": [
      "proof of concept"
    ],
    "example": ""
  },
  {
    "id": "term-62",
    "title": "Superficie de ataque",
    "category": "Vulnerabilidades",
    "description": "Conjunto de interfaces y componentes donde un adversario podría interactuar con un sistema.",
    "check": "Inventaría puntos expuestos, funciones innecesarias y límites de confianza.",
    "why": "Menos superficie reduce oportunidades potenciales de intrusión.",
    "aliases": [
      "attack surface"
    ],
    "example": ""
  },
  {
    "id": "term-63",
    "title": "Explotabilidad",
    "category": "Vulnerabilidades",
    "description": "Grado en que una debilidad puede aprovecharse bajo ciertas condiciones.",
    "check": "Valora prerequisitos, exposición, controles y evidencia disponible.",
    "why": "No basta el CVSS para conocer la probabilidad real de explotación.",
    "aliases": [
      "exploitability"
    ],
    "example": ""
  },
  {
    "id": "term-64",
    "title": "Backup incremental",
    "category": "Continuidad",
    "description": "Copia que incorpora cambios posteriores a un punto de referencia según la estrategia.",
    "check": "Comprueba restauración completa con su cadena de dependencias.",
    "why": "Una copia aislada puede no bastar para recuperar datos.",
    "aliases": [
      "copia incremental"
    ],
    "example": ""
  },
  {
    "id": "term-65",
    "title": "Backup inmutable",
    "category": "Continuidad",
    "description": "Copia protegida contra modificaciones o borrados durante una retención definida.",
    "check": "Verifica retención, segregación de permisos y restauración real.",
    "why": "Reduce el impacto de borrados maliciosos y ransomware.",
    "aliases": [
      "immutable backup",
      "WORM"
    ],
    "example": ""
  },
  {
    "id": "term-66",
    "title": "Regla 3-2-1",
    "category": "Continuidad",
    "description": "Guía habitual de copias: tres copias, dos medios y una fuera de ubicación.",
    "check": "Comprueba independencia, desconexión o inmutabilidad y procedimientos de restauración.",
    "why": "Es una guía, no garantía de recuperación por sí sola.",
    "aliases": [
      "3-2-1 backups"
    ],
    "example": ""
  },
  {
    "id": "term-67",
    "title": "Prueba de restauración",
    "category": "Continuidad",
    "description": "Ejercicio para recuperar datos o sistemas desde backups.",
    "check": "Mide tiempo, integridad, dependencias y resultados documentados.",
    "why": "Un backup que nunca se restaura no demuestra recuperabilidad.",
    "aliases": [
      "restore test"
    ],
    "example": ""
  },
  {
    "id": "term-68",
    "title": "Plan de continuidad (BCP)",
    "category": "Continuidad",
    "description": "Medidas organizativas para mantener funciones críticas durante incidentes.",
    "check": "Comprueba responsables, escenarios, dependencias, comunicación y ejercicios.",
    "why": "Prioriza procesos de negocio, no solo sistemas tecnológicos.",
    "aliases": [
      "business continuity plan"
    ],
    "example": ""
  },
  {
    "id": "term-69",
    "title": "Plan de recuperación (DRP)",
    "category": "Continuidad",
    "description": "Procedimientos técnicos y operativos para restaurar servicios después de un desastre.",
    "check": "Verifica responsables, orden de recuperación, RTO/RPO y pruebas.",
    "why": "Una recuperación improvisada suele ampliar los tiempos de parada.",
    "aliases": [
      "disaster recovery plan"
    ],
    "example": ""
  },
  {
    "id": "term-70",
    "title": "Alta disponibilidad",
    "category": "Continuidad",
    "description": "Diseño que busca reducir interrupciones mediante redundancia y conmutación.",
    "check": "Comprueba puntos únicos de fallo, failover y consistencia de datos.",
    "why": "No sustituye una estrategia de backup.",
    "aliases": [
      "HA",
      "failover"
    ],
    "example": ""
  },
  {
    "id": "term-71",
    "title": "Punto único de fallo",
    "category": "Continuidad",
    "description": "Elemento cuya indisponibilidad puede provocar la caída de un servicio completo.",
    "check": "Identifica dependencias críticas y verifica rutas o componentes alternativos.",
    "why": "Puede frustrar planes de continuidad aparentemente completos.",
    "aliases": [
      "SPOF",
      "single point of failure"
    ],
    "example": ""
  },
  {
    "id": "term-72",
    "title": "Integridad de evidencia",
    "category": "Evidencias",
    "description": "Capacidad de detectar alteraciones de un archivo respecto a una versión documentada.",
    "check": "Compara huellas, registra custodia y protege el original.",
    "why": "La integridad no identifica por sí sola quién capturó el dato.",
    "aliases": [
      "hash de evidencia"
    ],
    "example": ""
  },
  {
    "id": "term-73",
    "title": "Trazabilidad",
    "category": "Evidencias",
    "description": "Capacidad de relacionar un resultado con su activo, control, auditor y evidencia.",
    "check": "Comprueba identificadores, fechas, alcance y relaciones vigentes.",
    "why": "Permite sostener conclusiones y planificar una reevaluación.",
    "aliases": [
      "traceability"
    ],
    "example": ""
  },
  {
    "id": "term-74",
    "title": "Confidencialidad del expediente",
    "category": "Evidencias",
    "description": "Restricción de acceso a los documentos técnicos y datos del cliente.",
    "check": "Comprueba cifrado, permisos, destinatarios y eliminación segura.",
    "why": "Los informes pueden revelar detalles útiles para un atacante.",
    "aliases": [
      "custodia documental"
    ],
    "example": ""
  },
  {
    "id": "term-75",
    "title": "Hallazgo",
    "category": "Evidencias",
    "description": "Observación documentada que describe una condición relevante durante una auditoría.",
    "check": "Incluye activo, evidencia, impacto, recomendación y verificación.",
    "why": "No debe confundirse con una vulnerabilidad automáticamente confirmada.",
    "aliases": [
      "finding"
    ],
    "example": ""
  },
  {
    "id": "term-76",
    "title": "No verificado",
    "category": "Evidencias",
    "description": "Estado que indica falta de comprobación suficiente para emitir un resultado.",
    "check": "Registra qué prueba falta y por qué no se ha podido realizar.",
    "why": "No equivale a Conforme ni a No conforme.",
    "aliases": [
      "pendiente de verificar"
    ],
    "example": ""
  },
  {
    "id": "term-77",
    "title": "Amenaza",
    "category": "Riesgos",
    "description": "Evento o actor potencial capaz de causar daños sobre un activo.",
    "check": "Identifica escenarios relevantes para exposición y negocio.",
    "why": "Una amenaza no implica que exista una vulnerabilidad.",
    "aliases": [
      "threat"
    ],
    "example": ""
  },
  {
    "id": "term-78",
    "title": "Vulnerabilidad",
    "category": "Riesgos",
    "description": "Debilidad que podría permitir consecuencias no deseadas bajo determinadas condiciones.",
    "check": "Describe evidencia, activo, condiciones y posibilidad de explotación.",
    "why": "Una vulnerabilidad detectada necesita valoración contextual.",
    "aliases": [
      "debilidad"
    ],
    "example": ""
  },
  {
    "id": "term-79",
    "title": "Control compensatorio",
    "category": "Riesgos",
    "description": "Medida alternativa que reduce un riesgo cuando no puede aplicarse la corrección principal.",
    "check": "Comprueba efectividad, responsables, limitaciones y revisión periódica.",
    "why": "Puede disminuir riesgo residual, pero no siempre elimina la causa.",
    "aliases": [
      "compensating control"
    ],
    "example": ""
  },
  {
    "id": "term-80",
    "title": "Tratamiento del riesgo",
    "category": "Riesgos",
    "description": "Decisión de reducir, evitar, transferir o aceptar un riesgo según el contexto.",
    "check": "Registra aprobación, responsable, acción y plazo de revisión.",
    "why": "Distingue decisiones de negocio de correcciones técnicas.",
    "aliases": [
      "risk treatment"
    ],
    "example": ""
  },
  {
    "id": "term-81",
    "title": "Probabilidad",
    "category": "Riesgos",
    "description": "Estimación de que un escenario de riesgo ocurra en el contexto evaluado.",
    "check": "Explicita supuestos, exposición y datos que soportan la estimación.",
    "why": "La incertidumbre debe documentarse, no ocultarse.",
    "aliases": [
      "likelihood"
    ],
    "example": ""
  },
  {
    "id": "term-82",
    "title": "Impacto",
    "category": "Riesgos",
    "description": "Consecuencia para confidencialidad, integridad, disponibilidad o negocio.",
    "check": "Valora procesos, usuarios, datos afectados y duración.",
    "why": "Da sentido operativo a una severidad técnica.",
    "aliases": [
      "business impact"
    ],
    "example": ""
  },
  {
    "id": "term-83",
    "title": "Plan de remediación",
    "category": "Riesgos",
    "description": "Conjunto priorizado de acciones para tratar hallazgos documentados.",
    "check": "Registra responsables, fechas objetivo y criterios verificables de cierre.",
    "why": "Debe permitir actuar, no limitarse a enumerar recomendaciones.",
    "aliases": [
      "roadmap de seguridad"
    ],
    "example": ""
  },
  {
    "id": "term-84",
    "title": "Aceptación de riesgo",
    "category": "Riesgos",
    "description": "Decisión formal de convivir con un riesgo residual conocido.",
    "check": "Comprueba autoridad, justificación, vigencia y revisión futura.",
    "why": "Aceptar un riesgo no significa haberlo corregido.",
    "aliases": [
      "risk acceptance"
    ],
    "example": ""
  },
  {
    "id": "term-85",
    "title": "Modelo de responsabilidad compartida",
    "category": "Cloud y virtualización",
    "description": "Reparto de obligaciones de seguridad entre proveedor cloud y cliente.",
    "check": "Identifica responsabilidades para identidad, datos, red y configuración.",
    "why": "Usar cloud no traslada automáticamente toda la seguridad al proveedor.",
    "aliases": [
      "shared responsibility"
    ],
    "example": ""
  },
  {
    "id": "term-86",
    "title": "IaaS / PaaS / SaaS",
    "category": "Cloud y virtualización",
    "description": "Modelos cloud que ofrecen infraestructura, plataforma o software gestionado con responsabilidades diferentes.",
    "check": "Documenta modelo contratado y controles que siguen bajo el cliente.",
    "why": "Evita asumir que un servicio administrado está completamente protegido.",
    "aliases": [
      "cloud service models"
    ],
    "example": ""
  },
  {
    "id": "term-87",
    "title": "IAM cloud",
    "category": "Cloud y virtualización",
    "description": "Políticas y credenciales que controlan acceso a recursos cloud.",
    "check": "Revisa identidades, roles, MFA, claves y registros de acceso.",
    "why": "Una política demasiado amplia puede exponer múltiples recursos.",
    "aliases": [
      "identity and access management"
    ],
    "example": ""
  },
  {
    "id": "term-88",
    "title": "Bucket público",
    "category": "Cloud y virtualización",
    "description": "Almacenamiento de objetos accesible desde identidades o redes no previstas.",
    "check": "Comprueba políticas efectivas, cifrado, auditoría y exposición autorizada.",
    "why": "Puede permitir divulgar información sensible accidentalmente.",
    "aliases": [
      "object storage",
      "S3"
    ],
    "example": ""
  },
  {
    "id": "term-89",
    "title": "Snapshot",
    "category": "Cloud y virtualización",
    "description": "Copia de estado de una máquina virtual o volumen en un momento concreto.",
    "check": "Comprueba consistencia, retención, cifrado y procedimiento de recuperación.",
    "why": "No siempre sustituye una copia de seguridad independiente.",
    "aliases": [
      "instantánea"
    ],
    "example": ""
  },
  {
    "id": "term-90",
    "title": "Contenedor",
    "category": "Cloud y virtualización",
    "description": "Proceso aislado que comparte el kernel del sistema anfitrión.",
    "check": "Comprueba imágenes, privilegios, secretos, red y origen de dependencias.",
    "why": "El aislamiento mal configurado puede exponer al anfitrión.",
    "aliases": [
      "docker",
      "container"
    ],
    "example": ""
  },
  {
    "id": "term-91",
    "title": "Kubernetes",
    "category": "Cloud y virtualización",
    "description": "Plataforma de orquestación de aplicaciones en contenedores.",
    "check": "Revisa RBAC, secretos, políticas de red, imágenes y plano de control.",
    "why": "Su superficie de gestión requiere permisos estrictos.",
    "aliases": [
      "k8s"
    ],
    "example": ""
  },
  {
    "id": "term-92",
    "title": "Dato personal",
    "category": "Datos y privacidad",
    "description": "Información sobre una persona física identificada o identificable.",
    "check": "Localiza categorías, finalidad, accesos, conservación y transferencias.",
    "why": "Requiere medidas proporcionales de protección y gobernanza.",
    "aliases": [
      "RGPD",
      "GDPR"
    ],
    "example": ""
  },
  {
    "id": "term-93",
    "title": "Minimización de datos",
    "category": "Datos y privacidad",
    "description": "Principio de tratar solamente datos adecuados, pertinentes y necesarios para la finalidad.",
    "check": "Revisa campos recogidos, copias, destinatarios y conservación.",
    "why": "Reduce exposición si un expediente se pierde o comparte.",
    "aliases": [
      "data minimization"
    ],
    "example": ""
  },
  {
    "id": "term-94",
    "title": "Cifrado en reposo",
    "category": "Datos y privacidad",
    "description": "Protección criptográfica de información almacenada.",
    "check": "Verifica cobertura, claves, copias y procedimientos de recuperación.",
    "why": "Reduce divulgación cuando se pierde el soporte.",
    "aliases": [
      "encryption at rest"
    ],
    "example": ""
  },
  {
    "id": "term-95",
    "title": "Retención de datos",
    "category": "Datos y privacidad",
    "description": "Periodo establecido para conservar información según finalidad y obligaciones.",
    "check": "Comprueba política, calendarios, borrado y excepciones legales.",
    "why": "Guardar indefinidamente eleva riesgo de exposición.",
    "aliases": [
      "conservación"
    ],
    "example": ""
  },
  {
    "id": "term-96",
    "title": "Control de acceso",
    "category": "Datos y privacidad",
    "description": "Restricción de lectura, modificación o administración de datos y recursos.",
    "check": "Prueba autorización según rol y registro de accesos relevantes.",
    "why": "Evita que cualquier usuario consulte información fuera de su función.",
    "aliases": [
      "autorización"
    ],
    "example": ""
  },
  {
    "id": "term-97",
    "title": "SIEM",
    "category": "Operaciones y detección",
    "description": "Plataforma que centraliza y correlaciona eventos de seguridad.",
    "check": "Verifica fuentes, tiempos, reglas, responsables y respuesta a alertas.",
    "why": "Los eventos sin supervisión útil aportan poco valor.",
    "aliases": [
      "security information event management"
    ],
    "example": ""
  },
  {
    "id": "term-98",
    "title": "SOC",
    "category": "Operaciones y detección",
    "description": "Equipo o servicio encargado de monitorizar, investigar y responder a alertas de seguridad.",
    "check": "Comprueba cobertura, escalado, evidencias y tiempos de respuesta.",
    "why": "La herramienta no sustituye un proceso de respuesta.",
    "aliases": [
      "security operations center"
    ],
    "example": ""
  },
  {
    "id": "term-99",
    "title": "Registro de auditoría",
    "category": "Operaciones y detección",
    "description": "Evento almacenado que documenta una acción o cambio relevante.",
    "check": "Comprueba origen, integridad, retención, accesos y sincronización horaria.",
    "why": "Facilita investigar incidentes y demostrar acciones.",
    "aliases": [
      "logs",
      "audit log"
    ],
    "example": ""
  },
  {
    "id": "term-100",
    "title": "NTP",
    "category": "Operaciones y detección",
    "description": "Servicio o protocolo de sincronización horaria de sistemas.",
    "check": "Contrasta fuentes fiables y desviaciones entre equipos.",
    "why": "Fechas incoherentes dificultan correlacionar incidentes.",
    "aliases": [
      "network time protocol"
    ],
    "example": ""
  },
  {
    "id": "term-101",
    "title": "Indicador de compromiso (IoC)",
    "category": "Operaciones y detección",
    "description": "Artefacto observable asociado potencialmente a actividad maliciosa.",
    "check": "Correlaciona indicadores con contexto, fuentes y falsos positivos.",
    "why": "Un indicador aislado no prueba por sí mismo un incidente.",
    "aliases": [
      "indicator of compromise"
    ],
    "example": ""
  },
  {
    "id": "term-102",
    "title": "Respuesta a incidentes",
    "category": "Operaciones y detección",
    "description": "Proceso de preparación, identificación, contención, erradicación y recuperación.",
    "check": "Revisa roles, autorizaciones, simulacros y lecciones aprendidas.",
    "why": "Reduce tiempos y consecuencias cuando ocurre un incidente.",
    "aliases": [
      "incident response"
    ],
    "example": ""
  },
  {
    "id": "term-103",
    "title": "MTTD / MTTR",
    "category": "Operaciones y detección",
    "description": "Métricas de tiempo para detectar y responder o recuperar según su definición interna.",
    "check": "Verifica cómo se miden, desde qué momento y qué casos incluyen.",
    "why": "Una métrica sin definición uniforme puede inducir a error.",
    "aliases": [
      "mean time to detect",
      "mean time to respond"
    ],
    "example": ""
  },
  {
    "id": "term-104",
    "title": "Ransomware",
    "category": "Operaciones y detección",
    "description": "Malware y operaciones delictivas que pueden cifrar o exfiltrar información para extorsionar.",
    "check": "Revisa copias, privilegios, segmentación, detección y respuesta.",
    "why": "El impacto incluye indisponibilidad y posible fuga de datos.",
    "aliases": [
      "secuestro de datos"
    ],
    "example": ""
  }
]);
 const CATEGORIES=Object.freeze([...new Set(TERMS.map(t=>t.category))]);
 const normalize = input=>String(input??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('es').trim();
 const byId=id=>TERMS.find(t=>t.id===id)||null;
 const search=(query='',category='Todas')=>{
  const tokens=normalize(query).split(/\s+/).filter(Boolean);
  return TERMS.filter(t=>{
   if(category!=='Todas'&&t.category!==category)return false;
   if(!tokens.length)return true;
   const haystack=normalize([t.title,t.category,t.description,t.check,t.why,t.example,...(t.aliases||[])].join(' '));
   return tokens.every(token=>haystack.includes(token));
  }).sort((a,b)=>{
   if(!tokens.length)return a.title.localeCompare(b.title,'es');
   const score=t=>tokens.reduce((sum,word)=>{
    const title=normalize(t.title),aliases=(t.aliases||[]).map(normalize);
    return sum+(title.startsWith(word)?8:title.includes(word)?5:aliases.some(x=>x.includes(word))?4:0);
   },0);
   return score(b)-score(a)||a.title.localeCompare(b.title,'es');
  });
 };
 globalThis.AuditGlossary=Object.freeze({TERMS,CATEGORIES,search,byId,normalize});
})();
