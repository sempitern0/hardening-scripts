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
    "aliases": [
      "Virtual Local Area Network"
    ],
    "example": "",
    "fullName": "Virtual Local Area Network",
    "references": [
      {
        "label": "Estándares IEEE 802.1Q (consulta la norma vigente)",
        "url": "https://standards.ieee.org/"
      }
    ]
  },
  {
    "id": "term-3",
    "title": "CIDR",
    "category": "Redes",
    "description": "Notación que expresa dirección de red y longitud del prefijo, por ejemplo 192.168.10.0/24.",
    "check": "Valida solapamientos y comprueba si las rutas permiten el tráfico esperado.",
    "why": "Un prefijo mal definido puede ampliar el alcance o provocar solapamientos.",
    "aliases": [
      "Classless Inter-Domain Routing"
    ],
    "example": "",
    "fullName": "Classless Inter-Domain Routing",
    "references": [
      {
        "label": "IANA - registros de direcciones IP",
        "url": "https://www.iana.org/numbers"
      }
    ]
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
      "autenticación multifactor",
      "Multi-Factor Authentication"
    ],
    "example": "",
    "fullName": "Multi-Factor Authentication",
    "references": [
      {
        "label": "Guías NIST de identidad digital",
        "url": "https://pages.nist.gov/800-63-4/"
      }
    ]
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
    "aliases": [
      "Common Vulnerabilities and Exposures"
    ],
    "example": "",
    "fullName": "Common Vulnerabilities and Exposures",
    "references": [
      {
        "label": "CVE Program",
        "url": "https://www.cve.org/"
      },
      {
        "label": "NVD - búsqueda de CVE",
        "url": "https://nvd.nist.gov/vuln/search"
      },
      {
        "label": "CISA KEV",
        "url": "https://www.cisa.gov/known-exploited-vulnerabilities-catalog"
      }
    ]
  },
  {
    "id": "term-8",
    "title": "CVSS",
    "category": "Vulnerabilidades",
    "description": "Sistema de puntuación de características técnicas de vulnerabilidades.",
    "check": "No lo uses como única medida de riesgo; considera exposición y criticidad del activo.",
    "why": "Una puntuación técnica no sustituye la evaluación de riesgo de negocio.",
    "aliases": [
      "Common Vulnerability Scoring System"
    ],
    "example": "",
    "fullName": "Common Vulnerability Scoring System",
    "references": [
      {
        "label": "FIRST CVSS",
        "url": "https://www.first.org/cvss/"
      },
      {
        "label": "NVD",
        "url": "https://nvd.nist.gov/"
      }
    ]
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
    "aliases": [
      "Endpoint Detection and Response"
    ],
    "example": "",
    "fullName": "Endpoint Detection and Response",
    "references": [
      {
        "label": "MITRE ATT&CK para detección y contexto",
        "url": "https://attack.mitre.org/"
      }
    ]
  },
  {
    "id": "term-11",
    "title": "Hardening",
    "category": "Sistemas",
    "description": "Reducción de superficie de ataque mediante configuración segura.",
    "check": "Contrasta la configuración efectiva con una referencia apropiada y documenta excepciones.",
    "why": "Reduce servicios, permisos y configuraciones innecesarias.",
    "aliases": [],
    "example": "",
    "references": [
      {
        "label": "CIS Benchmarks",
        "url": "https://www.cisecurity.org/cis-benchmarks"
      },
      {
        "label": "NIST CSF",
        "url": "https://www.nist.gov/cyberframework"
      }
    ]
  },
  {
    "id": "term-12",
    "title": "RPO",
    "category": "Continuidad",
    "description": "Pérdida máxima de datos tolerada, expresada como intervalo temporal.",
    "check": "Contrasta RPO acordado con frecuencia y resultados de copias.",
    "why": "Ayuda a determinar cuántos datos puede tolerar perder el negocio.",
    "aliases": [
      "Recovery Point Objective"
    ],
    "example": "Ejemplo: un RPO de 4 horas permite perder hasta cuatro horas de cambios.",
    "fullName": "Recovery Point Objective",
    "references": [
      {
        "label": "NIST: continuidad y recuperación",
        "url": "https://csrc.nist.gov/pubs/sp/800/34/r1/upd1/final"
      }
    ]
  },
  {
    "id": "term-13",
    "title": "RTO",
    "category": "Continuidad",
    "description": "Tiempo objetivo para recuperar un servicio después de una interrupción.",
    "check": "Comprueba con pruebas de restauración y dependencias reales.",
    "why": "Ayuda a planificar cuándo debe volver a operar un servicio.",
    "aliases": [
      "Recovery Time Objective"
    ],
    "example": "Ejemplo: un RTO de 2 horas fija la recuperación objetivo del servicio.",
    "fullName": "Recovery Time Objective",
    "references": [
      {
        "label": "NIST: planes de contingencia",
        "url": "https://csrc.nist.gov/pubs/sp/800/34/r1/upd1/final"
      }
    ]
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
    "aliases": [
      "Network Address Translation"
    ],
    "example": "",
    "fullName": "Network Address Translation",
    "references": [
      {
        "label": "RFC 3022: NAT tradicional",
        "url": "https://www.rfc-editor.org/rfc/rfc3022"
      }
    ]
  },
  {
    "id": "term-19",
    "title": "VPN",
    "category": "Redes",
    "description": "Canal protegido entre extremos o redes sobre un transporte no confiable.",
    "check": "Comprueba autenticación, algoritmos, segmentación y revocación.",
    "why": "Protege tránsito, pero necesita autenticación y acceso delimitado.",
    "aliases": [
      "Virtual Private Network"
    ],
    "example": "",
    "fullName": "Virtual Private Network",
    "references": [
      {
        "label": "Catálogo de especificaciones RFC",
        "url": "https://www.rfc-editor.org/"
      }
    ]
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
      "lista de control de acceso",
      "Access Control List"
    ],
    "example": "",
    "fullName": "Access Control List",
    "references": [
      {
        "label": "Glosario NIST",
        "url": "https://csrc.nist.gov/glossary/term/access_control_list"
      }
    ]
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
      "domain name system",
      "Domain Name System"
    ],
    "example": "",
    "fullName": "Domain Name System",
    "references": [
      {
        "label": "IANA - zonas raíz",
        "url": "https://www.iana.org/domains/root/db"
      },
      {
        "label": "RFC Editor",
        "url": "https://www.rfc-editor.org/"
      }
    ]
  },
  {
    "id": "term-26",
    "title": "DHCP",
    "category": "Redes",
    "description": "Protocolo que asigna automáticamente configuración IP a los equipos.",
    "check": "Verifica rangos, reservas, opciones críticas y servidores autorizados.",
    "why": "Un servidor DHCP no autorizado puede desviar tráfico.",
    "aliases": [
      "asignación automática IP",
      "Dynamic Host Configuration Protocol"
    ],
    "example": "",
    "fullName": "Dynamic Host Configuration Protocol",
    "references": [
      {
        "label": "RFC 2131: DHCP",
        "url": "https://www.rfc-editor.org/rfc/rfc2131"
      }
    ]
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
    "example": "",
    "references": [
      {
        "label": "IANA - puertos y servicios",
        "url": "https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml"
      }
    ]
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
      "SSL",
      "Transport Layer Security"
    ],
    "example": "",
    "fullName": "Transport Layer Security",
    "references": [
      {
        "label": "RFC 8446: TLS 1.3",
        "url": "https://www.rfc-editor.org/rfc/rfc8446"
      }
    ]
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
    "example": "",
    "references": [
      {
        "label": "NIST SP 800-207",
        "url": "https://csrc.nist.gov/pubs/sp/800/207/final"
      }
    ]
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
    "example": "",
    "references": [
      {
        "label": "CIS Benchmarks",
        "url": "https://www.cisecurity.org/cis-benchmarks"
      },
      {
        "label": "CIS Controls",
        "url": "https://www.cisecurity.org/controls"
      }
    ]
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
    "example": "",
    "references": [
      {
        "label": "IANA - puertos y servicios",
        "url": "https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml"
      }
    ]
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
      "trusted platform module",
      "Trusted Platform Module"
    ],
    "example": "",
    "fullName": "Trusted Platform Module",
    "references": [
      {
        "label": "Trusted Computing Group: TPM",
        "url": "https://trustedcomputinggroup.org/resource/tpm-library-specification/"
      }
    ]
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
      "software bill of materials",
      "Software Bill of Materials"
    ],
    "example": "",
    "fullName": "Software Bill of Materials",
    "references": [
      {
        "label": "CISA: inventario de componentes de software",
        "url": "https://www.cisa.gov/sbom"
      }
    ]
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
      "directorio LDAP",
      "Lightweight Directory Access Protocol / LDAP over TLS"
    ],
    "example": "",
    "fullName": "Lightweight Directory Access Protocol / LDAP over TLS",
    "references": [
      {
        "label": "RFC 4511: LDAP",
        "url": "https://www.rfc-editor.org/rfc/rfc4511"
      }
    ]
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
      "privileged access management",
      "Privileged Access Management"
    ],
    "example": "",
    "fullName": "Privileged Access Management",
    "references": [
      {
        "label": "NIST: controles de privilegios",
        "url": "https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final"
      }
    ]
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
      "single sign-on",
      "Single Sign-On"
    ],
    "example": "",
    "fullName": "Single Sign-On",
    "references": [
      {
        "label": "NIST: identidad y federación",
        "url": "https://pages.nist.gov/800-63-4/"
      }
    ]
  },
  {
    "id": "term-53",
    "title": "RBAC",
    "category": "Identidad",
    "description": "Modelo de permisos basado en funciones o roles definidos.",
    "check": "Revisa asignaciones, separación de tareas y privilegios acumulados.",
    "why": "Facilita limitar permisos por necesidad operativa.",
    "aliases": [
      "role based access control",
      "Role-Based Access Control"
    ],
    "example": "",
    "fullName": "Role-Based Access Control",
    "references": [
      {
        "label": "NIST: RBAC",
        "url": "https://csrc.nist.gov/projects/role-based-access-control"
      }
    ]
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
      "common weakness enumeration",
      "Common Weakness Enumeration"
    ],
    "example": "",
    "fullName": "Common Weakness Enumeration",
    "references": [
      {
        "label": "Catálogo de debilidades de software",
        "url": "https://cwe.mitre.org/"
      }
    ]
  },
  {
    "id": "term-57",
    "title": "CPE",
    "category": "Vulnerabilidades",
    "description": "Identificador estandarizado de productos y plataformas utilizado en correlación de vulnerabilidades.",
    "check": "Confirma que la versión y la variante corresponden al activo real.",
    "why": "Las coincidencias imprecisas causan falsos positivos.",
    "aliases": [
      "common platform enumeration",
      "Common Platform Enumeration"
    ],
    "example": "",
    "fullName": "Common Platform Enumeration",
    "references": [
      {
        "label": "Nomenclatura de plataformas de NVD",
        "url": "https://nvd.nist.gov/products/cpe"
      }
    ]
  },
  {
    "id": "term-58",
    "title": "EPSS",
    "category": "Vulnerabilidades",
    "description": "Estimación probabilística de que una CVE se explote durante un horizonte temporal.",
    "check": "Registra fecha y fuente de la consulta; combina con exposición y riesgo de negocio.",
    "why": "Aporta señal de priorización, no prueba explotación ni compromiso.",
    "aliases": [
      "exploit prediction scoring system",
      "Exploit Prediction Scoring System"
    ],
    "example": "",
    "fullName": "Exploit Prediction Scoring System",
    "references": [
      {
        "label": "Modelo de probabilidad de explotación FIRST",
        "url": "https://www.first.org/epss/"
      }
    ]
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
      "KEV",
      "Known Exploited Vulnerabilities Catalog"
    ],
    "example": "",
    "fullName": "Known Exploited Vulnerabilities Catalog",
    "references": [
      {
        "label": "Catálogo CISA de vulnerabilidades explotadas",
        "url": "https://www.cisa.gov/known-exploited-vulnerabilities-catalog"
      }
    ]
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
      "security information event management",
      "Security Information and Event Management"
    ],
    "example": "",
    "fullName": "Security Information and Event Management",
    "references": [
      {
        "label": "NIST: gestión de logs de seguridad",
        "url": "https://csrc.nist.gov/pubs/sp/800/92/final"
      }
    ]
  },
  {
    "id": "term-98",
    "title": "SOC",
    "category": "Operaciones y detección",
    "description": "Equipo o servicio encargado de monitorizar, investigar y responder a alertas de seguridad.",
    "check": "Comprueba cobertura, escalado, evidencias y tiempos de respuesta.",
    "why": "La herramienta no sustituye un proceso de respuesta.",
    "aliases": [
      "security operations center",
      "Security Operations Center"
    ],
    "example": "",
    "fullName": "Security Operations Center",
    "references": [
      {
        "label": "NIST: respuesta a incidentes",
        "url": "https://csrc.nist.gov/pubs/sp/800/61/r3/final"
      }
    ]
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
      "network time protocol",
      "Network Time Protocol"
    ],
    "example": "",
    "fullName": "Network Time Protocol",
    "references": [
      {
        "label": "RFC 5905: NTP",
        "url": "https://www.rfc-editor.org/rfc/rfc5905"
      }
    ]
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
    "example": "",
    "references": [
      {
        "label": "MITRE ATT&CK",
        "url": "https://attack.mitre.org/"
      }
    ]
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
    "help": {
      "region": "España",
      "organization": "INCIBE",
      "title": "Línea de Ayuda en Ciberseguridad",
      "phone": "017",
      "guidance": "Servicio gratuito y confidencial de orientación para ciudadanos y empresas ante dudas o problemas de ciberseguridad. Si el incidente está activo, sigue también el plan de respuesta y los canales internos establecidos.",
      "officialUrl": "https://www.incibe.es/linea-de-ayuda-en-ciberseguridad",
      "reportUrl": "https://www.incibe.es/empresas/te-ayudamos/reporta-tu-incidente",
      "reporting": "Para comunicar un incidente de una empresa, consulta la vía correspondiente de INCIBE-CERT. El 017 es una línea de orientación, no sustituye la notificación formal ni las obligaciones aplicables.",
      "privacy": "Evita compartir contraseñas, claves o evidencias sensibles sin autorización."
    },
    "example": "",
    "references": [
      {
        "label": "NIST SP 800-61",
        "url": "https://csrc.nist.gov/pubs/sp/800/61/r3/final"
      }
    ]
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
  },
  {
    "id": "term-105",
    "title": "ISO/IEC 27001",
    "category": "Normativa y estándares",
    "description": "Norma de sistemas de gestión de seguridad de la información (SGSI).",
    "check": "Revisa alcance, análisis de riesgos, declaración de aplicabilidad, auditorías internas y tratamiento.",
    "why": "Certificación de un alcance no garantiza que todos los activos estén cubiertos.",
    "aliases": [
      "Information security management systems"
    ],
    "example": "",
    "fullName": "Information security management systems",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.iso.org/isoiec-27001-information-security.html"
      }
    ]
  },
  {
    "id": "term-106",
    "title": "ISO/IEC 27002",
    "category": "Normativa y estándares",
    "description": "Guía de controles de seguridad de la información, utilizada como referencia para seleccionar medidas.",
    "check": "Relaciona controles elegidos con los riesgos, evidencias y su aplicabilidad.",
    "why": "No es una certificación independiente de seguridad.",
    "aliases": [
      "Information security controls"
    ],
    "example": "",
    "fullName": "Information security controls",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.iso.org/standard/75652.html"
      }
    ]
  },
  {
    "id": "term-107",
    "title": "ISO/IEC 27005",
    "category": "Normativa y estándares",
    "description": "Orientaciones para gestionar riesgos de seguridad de la información.",
    "check": "Valida metodología, criterios de aceptación y propietarios de riesgos.",
    "why": "Una matriz de riesgos sin evidencias ni seguimiento no acredita gestión.",
    "aliases": [
      "Guidance on managing information security risks"
    ],
    "example": "",
    "fullName": "Guidance on managing information security risks",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.iso.org/search.html?q=ISO%2FIEC%2027005"
      }
    ]
  },
  {
    "id": "term-108",
    "title": "ISO/IEC 27701",
    "category": "Normativa y estándares",
    "description": "Requisitos y orientaciones para la gestión de información de privacidad (PIMS).",
    "check": "Comprueba alcance, roles de responsable/encargado y controles de privacidad.",
    "why": "No sustituye la evaluación de obligaciones legales de protección de datos.",
    "aliases": [
      "Privacy information management system"
    ],
    "example": "",
    "fullName": "Privacy information management system",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.iso.org/search.html?q=ISO%2FIEC%2027701"
      }
    ]
  },
  {
    "id": "term-109",
    "title": "ISO 22301",
    "category": "Normativa y estándares",
    "description": "Norma de gestión de continuidad de negocio (BCMS).",
    "check": "Revisa BIA, estrategias, escenarios, ensayos y revisión de objetivos RTO/RPO.",
    "why": "Tener documentos no prueba que la recuperación cumpla los objetivos.",
    "aliases": [
      "Business continuity management systems"
    ],
    "example": "",
    "fullName": "Business continuity management systems",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.iso.org/standard/75106.html"
      }
    ]
  },
  {
    "id": "term-110",
    "title": "NIST CSF",
    "category": "Normativa y estándares",
    "description": "Marco de ciberseguridad NIST para gestionar riesgos con funciones y perfiles.",
    "check": "Contrasta funciones Identify, Protect, Detect, Respond, Recover y Govern contra resultados observables.",
    "why": "No confundir uso voluntario del marco con una certificación.",
    "aliases": [
      "National Institute of Standards and Technology Cybersecurity Framework"
    ],
    "example": "",
    "fullName": "National Institute of Standards and Technology Cybersecurity Framework",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.nist.gov/cyberframework"
      }
    ]
  },
  {
    "id": "term-111",
    "title": "NIST SP 800-53",
    "category": "Normativa y estándares",
    "description": "Catálogo de controles de seguridad y privacidad para sistemas y organizaciones.",
    "check": "Identifica revisión y baseline utilizados y vincula cada control a evidencias.",
    "why": "Las recomendaciones requieren adaptación al alcance y normativa.",
    "aliases": [
      "NIST Special Publication 800-53"
    ],
    "example": "",
    "fullName": "NIST Special Publication 800-53",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final"
      }
    ]
  },
  {
    "id": "term-112",
    "title": "NIST SP 800-61",
    "category": "Normativa y estándares",
    "description": "Guía de respuesta a incidentes de ciberseguridad.",
    "check": "Comprueba preparación, capacidad de respuesta y mejora continua.",
    "why": "Una guía no sustituye un plan operativo ejercitado.",
    "aliases": [
      "NIST Special Publication 800-61"
    ],
    "example": "",
    "fullName": "NIST Special Publication 800-61",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://csrc.nist.gov/pubs/sp/800/61/r3/final"
      }
    ]
  },
  {
    "id": "term-113",
    "title": "CIS Controls",
    "category": "Normativa y estándares",
    "description": "Controles de ciberseguridad priorizados del Center for Internet Security.",
    "check": "Verifica grupo de implementación, salvaguardas elegidas y evidencia de ejecución.",
    "why": "No equivale a los CIS Benchmarks de configuración de producto.",
    "aliases": [
      "Center for Internet Security Controls"
    ],
    "example": "",
    "fullName": "Center for Internet Security Controls",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.cisecurity.org/controls"
      }
    ]
  },
  {
    "id": "term-114",
    "title": "OWASP Top 10",
    "category": "Normativa y estándares",
    "description": "Documento de concienciación sobre riesgos de seguridad en aplicaciones web.",
    "check": "Relaciona categorías aplicables con pruebas autorizadas y evidencias técnicas.",
    "why": "No constituye una lista exhaustiva de vulnerabilidades ni un test de penetración.",
    "aliases": [
      "Open Worldwide Application Security Project Top 10"
    ],
    "example": "",
    "fullName": "Open Worldwide Application Security Project Top 10",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://owasp.org/www-project-top-ten/"
      }
    ]
  },
  {
    "id": "term-115",
    "title": "RFC",
    "category": "Organismos y registros",
    "description": "Publicación técnica de la serie Request for Comments que documenta protocolos y prácticas de Internet.",
    "check": "Identifica RFC exacta, estado, actualizaciones y obsolescencias antes de citarla.",
    "why": "No todas las RFC son normas de Internet ni tienen la misma vigencia.",
    "aliases": [
      "Request for Comments"
    ],
    "example": "",
    "fullName": "Request for Comments",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.rfc-editor.org/"
      }
    ]
  },
  {
    "id": "term-116",
    "title": "IETF",
    "category": "Organismos y registros",
    "description": "Comunidad abierta responsable de numerosos estándares y protocolos de Internet.",
    "check": "Consulta estándares y documentos vigentes y grupos de trabajo.",
    "why": "Un borrador Internet-Draft puede cambiar o caducar.",
    "aliases": [
      "Internet Engineering Task Force"
    ],
    "example": "",
    "fullName": "Internet Engineering Task Force",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.ietf.org/"
      }
    ]
  },
  {
    "id": "term-117",
    "title": "IANA",
    "category": "Organismos y registros",
    "description": "Autoridad coordinadora de registros globales de parámetros, números y nombres de Internet.",
    "check": "Comprueba asignaciones oficiales de puertos, protocolos, dominios y espacios IP.",
    "why": "La asignación de un puerto no demuestra que exista un servicio legítimo.",
    "aliases": [
      "Internet Assigned Numbers Authority"
    ],
    "example": "",
    "fullName": "Internet Assigned Numbers Authority",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.iana.org/"
      }
    ]
  },
  {
    "id": "term-118",
    "title": "ICANN",
    "category": "Organismos y registros",
    "description": "Organización de coordinación de identificadores únicos de Internet y el sistema de nombres.",
    "check": "Contrasta estructura de TLD y políticas de registro con fuentes oficiales.",
    "why": "No sustituye a un registrador o al registro de un TLD concreto.",
    "aliases": [
      "Internet Corporation for Assigned Names and Numbers"
    ],
    "example": "",
    "fullName": "Internet Corporation for Assigned Names and Numbers",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.icann.org/"
      }
    ]
  },
  {
    "id": "term-119",
    "title": "NVD",
    "category": "Vulnerabilidades",
    "description": "Base de datos estadounidense de información sobre vulnerabilidades que enriquece registros CVE.",
    "check": "Comprueba identificador, historial, fuentes, métricas y asignación CPE.",
    "why": "Las métricas NVD pueden diferir de las publicadas por el fabricante.",
    "aliases": [
      "National Vulnerability Database"
    ],
    "example": "",
    "fullName": "National Vulnerability Database",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://nvd.nist.gov/vuln/search"
      }
    ]
  },
  {
    "id": "term-120",
    "title": "CNA",
    "category": "Vulnerabilidades",
    "description": "Organización autorizada para asignar identificadores CVE en su alcance.",
    "check": "Identifica la entidad emisora, avisos y correcciones del proveedor.",
    "why": "La emisión de una CVE no prueba afectación de un activo concreto.",
    "aliases": [
      "CVE Numbering Authority"
    ],
    "example": "",
    "fullName": "CVE Numbering Authority",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.cve.org/ProgramOrganization/CNAs"
      }
    ]
  },
  {
    "id": "term-121",
    "title": "PKI",
    "category": "Identidad",
    "description": "Infraestructura de claves públicas que gestiona certificados, autoridades y revocación.",
    "check": "Revisa raíces de confianza, cadena, ciclo de vida y revocación.",
    "why": "Un certificado emitido no implica que los clientes lo validen correctamente.",
    "aliases": [
      "Public Key Infrastructure"
    ],
    "example": "",
    "fullName": "Public Key Infrastructure",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://csrc.nist.gov/glossary/term/public_key_infrastructure"
      }
    ]
  },
  {
    "id": "term-122",
    "title": "RADIUS",
    "category": "Identidad",
    "description": "Protocolo de autenticación, autorización y contabilidad para acceso de red.",
    "check": "Verifica integridad de clientes NAS, políticas y registro de autenticaciones.",
    "why": "El uso de RADIUS no garantiza por sí mismo MFA ni segmentación.",
    "aliases": [
      "Remote Authentication Dial-In User Service"
    ],
    "example": "",
    "fullName": "Remote Authentication Dial-In User Service",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.rfc-editor.org/rfc/rfc2865"
      }
    ]
  },
  {
    "id": "term-123",
    "title": "802.1X",
    "category": "Redes",
    "description": "Control de acceso a redes basado en puerto; involucra supplicant, authenticator y autenticador backend.",
    "check": "Comprueba modo de autenticación, VLAN asignada y excepciones en los switches.",
    "why": "Diferencia 802.1X del protocolo EAP y de un producto NAC.",
    "aliases": [
      "IEEE 802.1X Port-Based Network Access Control"
    ],
    "example": "",
    "fullName": "IEEE 802.1X Port-Based Network Access Control",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://standards.ieee.org/"
      }
    ]
  },
  {
    "id": "term-124",
    "title": "BIA",
    "category": "Continuidad",
    "description": "Análisis de impacto en el negocio que identifica procesos críticos y dependencias.",
    "check": "Verifica criterios, impactos temporales, propietarios y prioridades.",
    "why": "No puede inferirse RTO/RPO sin necesidades reales del negocio.",
    "aliases": [
      "Business Impact Analysis"
    ],
    "example": "",
    "fullName": "Business Impact Analysis",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://csrc.nist.gov/pubs/sp/800/34/r1/upd1/final"
      }
    ]
  },
  {
    "id": "term-125",
    "title": "SLA",
    "category": "Continuidad",
    "description": "Compromiso de niveles de servicio con indicadores y obligaciones acordadas.",
    "check": "Contrasta umbrales, medición, exclusiones y penalizaciones aplicables.",
    "why": "Una promesa de disponibilidad no sustituye pruebas de resiliencia.",
    "aliases": [
      "Service Level Agreement"
    ],
    "example": "",
    "fullName": "Service Level Agreement",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://csrc.nist.gov/glossary/term/service_level_agreement"
      }
    ]
  },
  {
    "id": "term-126",
    "title": "CVE ID vs CWE",
    "category": "Vulnerabilidades",
    "description": "CVE identifica una vulnerabilidad concreta; CWE clasifica una clase de debilidad.",
    "check": "Relaciona hallazgos verificados con la debilidad técnica correspondiente.",
    "why": "No asignar CVE a errores genéricos sin identificador reconocido.",
    "aliases": [
      "CVE versus CWE"
    ],
    "example": "",
    "fullName": "CVE versus CWE",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://cwe.mitre.org/"
      }
    ]
  },
  {
    "id": "term-127",
    "title": "SPF",
    "category": "Redes",
    "description": "Política DNS para identificar los servidores autorizados a enviar correo por un dominio.",
    "check": "Comprueba TXT SPF y alineación con servicios emisores; revisa límite de búsquedas.",
    "why": "SPF por sí solo no demuestra protección antisuplantación completa.",
    "aliases": [
      "Sender Policy Framework"
    ],
    "example": "",
    "fullName": "Sender Policy Framework",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.rfc-editor.org/rfc/rfc7208"
      }
    ]
  },
  {
    "id": "term-128",
    "title": "DKIM",
    "category": "Redes",
    "description": "Firma criptográfica asociada al dominio que permite verificar integridad y autoría de correo.",
    "check": "Comprueba selector DNS, algoritmo, firma y estado de rotación.",
    "why": "DKIM válido no prueba que el mensaje sea seguro.",
    "aliases": [
      "DomainKeys Identified Mail"
    ],
    "example": "",
    "fullName": "DomainKeys Identified Mail",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.rfc-editor.org/rfc/rfc6376"
      }
    ]
  },
  {
    "id": "term-129",
    "title": "DMARC",
    "category": "Redes",
    "description": "Política para tratar mensajes que fallan alineación SPF y DKIM.",
    "check": "Verifica política DNS, alineación y tratamiento de informes.",
    "why": "p=none solo monitoriza; no rechaza mensajes por política DMARC.",
    "aliases": [
      "Domain-based Message Authentication, Reporting and Conformance"
    ],
    "example": "",
    "fullName": "Domain-based Message Authentication, Reporting and Conformance",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.rfc-editor.org/rfc/rfc7489"
      }
    ]
  },
  {
    "id": "term-130",
    "title": "DNSSEC",
    "category": "Redes",
    "description": "Extensiones de DNS que permiten validar autenticidad e integridad de datos de zona.",
    "check": "Comprueba DS, DNSKEY, RRSIG y funcionamiento de validadores.",
    "why": "DNSSEC no cifra consultas DNS ni sustituye privacidad.",
    "aliases": [
      "Domain Name System Security Extensions"
    ],
    "example": "",
    "fullName": "Domain Name System Security Extensions",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.rfc-editor.org/rfc/rfc4035"
      }
    ]
  },
  {
    "id": "term-131",
    "title": "HTTP Security Headers",
    "category": "Aplicaciones y servicios",
    "description": "Cabeceras de respuesta HTTP que ayudan a reducir determinados riesgos web.",
    "check": "Comprueba HSTS, CSP, X-Content-Type-Options y Referrer-Policy.",
    "why": "Una cabecera aislada no acredita seguridad general de la aplicación.",
    "aliases": [
      "HTTP response security headers"
    ],
    "example": "",
    "fullName": "HTTP response security headers",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://owasp.org/www-project-secure-headers/"
      }
    ]
  },
  {
    "id": "term-132",
    "title": "CSP",
    "category": "Aplicaciones y servicios",
    "description": "Política del navegador que limita fuentes de contenido y ciertos comportamientos.",
    "check": "Revisa cabeceras efectivas y excepciones inseguras en directivas.",
    "why": "CSP no sustituye saneamiento de entradas ni diseño seguro.",
    "aliases": [
      "Content Security Policy"
    ],
    "example": "",
    "fullName": "Content Security Policy",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP"
      }
    ]
  },
  {
    "id": "term-133",
    "title": "HSTS",
    "category": "Aplicaciones y servicios",
    "description": "Política HTTP que indica a los navegadores usar HTTPS para un host.",
    "check": "Comprueba max-age, includeSubDomains y cobertura real de TLS.",
    "why": "No sustituye certificados válidos ni cubre clientes que no respeten HSTS.",
    "aliases": [
      "HTTP Strict Transport Security"
    ],
    "example": "",
    "fullName": "HTTP Strict Transport Security",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://www.rfc-editor.org/rfc/rfc6797"
      }
    ]
  },
  {
    "id": "term-134",
    "title": "OWASP ASVS",
    "category": "Aplicaciones y servicios",
    "description": "Estándar de verificación de controles técnicos de seguridad de aplicaciones.",
    "check": "Ajusta nivel de verificación a riesgo y alcance; conserva pruebas reproducibles.",
    "why": "No asumas cumplimiento sin evidencia detallada.",
    "aliases": [
      "Application Security Verification Standard"
    ],
    "example": "",
    "fullName": "Application Security Verification Standard",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://owasp.org/www-project-application-security-verification-standard/"
      }
    ]
  },
  {
    "id": "term-135",
    "title": "SAST / DAST",
    "category": "Aplicaciones y servicios",
    "description": "Análisis de seguridad estático del código y dinámico de aplicaciones en ejecución.",
    "check": "Contrasta cobertura, reglas, autenticación de pruebas y falsos positivos.",
    "why": "Ninguna modalidad sustituye una revisión manual contextualizada.",
    "aliases": [
      "Static Application Security Testing / Dynamic Application Security Testing"
    ],
    "example": "",
    "fullName": "Static Application Security Testing / Dynamic Application Security Testing",
    "references": [
      {
        "label": "Referencia oficial",
        "url": "https://owasp.org/"
      }
    ]
  }
]);
 // Read-only diagnostic playbooks. Commands are examples, NEVER executed by this PWA.
 // Replace .invalid hosts and illustrative paths with explicitly authorized assets.
 const GUIDES=Object.freeze(Object.fromEntries([
  {
    "id": "term-1",
    "symptom": "Una zona de invitados llega a servicios internos.",
    "verify": "Contrasta origen, rutas y política del firewall; prueba solo destinos autorizados.",
    "interpret": "Una ruta disponible no demuestra acceso: correlaciona con la ACL y el resultado de conexión.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ip route show",
        "lookFor": "Ruta y puerta de enlace hacia el segmento revisado."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetRoute | Sort-Object DestinationPrefix",
        "lookFor": "Prefijos y rutas efectivas del equipo."
      },
      {
        "platform": "PowerShell · red",
        "command": "Test-NetConnection -ComputerName servidor.autorizado.invalid -Port 443",
        "lookFor": "TcpTestSucceeded y origen; sustituye el host tras autorizar la prueba."
      }
    ]
  },
  {
    "id": "term-2",
    "symptom": "Tráfico entre VLAN inesperadas o pérdida de conectividad.",
    "verify": "Comprueba etiquetado en interfaz, trunk y política entre VLAN.",
    "interpret": "La VLAN local no refleja por sí sola la configuración completa del switch.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ip -d link show",
        "lookFor": "Subinterfaces 802.1Q, VLAN ID y estado del enlace."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetAdapter | Format-Table Name,Status,LinkSpeed",
        "lookFor": "Adaptadores, estado y velocidad; el VLAN ID puede exigir herramienta del fabricante."
      }
    ]
  },
  {
    "id": "term-3",
    "symptom": "Dos redes parecen solaparse o una ruta envía tráfico a otro destino.",
    "verify": "Compara máscara, prefijos y tabla de rutas.",
    "interpret": "Prefijos más específicos prevalecen; documenta rutas asimétricas o solapadas.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ip -4 address show",
        "lookFor": "Dirección y longitud del prefijo de cada interfaz."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetIPAddress -AddressFamily IPv4",
        "lookFor": "IPAddress y PrefixLength de cada interfaz."
      }
    ]
  },
  {
    "id": "term-4",
    "symptom": "Un equipo publicado tiene acceso innecesario a gestión interna.",
    "verify": "Documenta flujos permitidos de la DMZ hacia LAN y políticas de salida.",
    "interpret": "La mera existencia de la DMZ no acredita aislamiento.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ip route get 192.0.2.10",
        "lookFor": "Interfaz y siguiente salto elegidos para un destino de documentación (reemplazar IP)."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetFirewallRule -PolicyStore ActiveStore | Where-Object Enabled -eq 'True' | Select-Object -First 30 DisplayName,Direction,Action",
        "lookFor": "Muestra reglas locales activas; para la política perimetral consulta el firewall central."
      }
    ]
  },
  {
    "id": "term-5",
    "symptom": "Hay sesiones privilegiadas sin segundo factor.",
    "verify": "Revisa políticas y excepciones desde la consola del proveedor de identidad.",
    "interpret": "Los comandos del equipo no prueban por sí solos que el IdP exija MFA.",
    "commands": [
      {
        "platform": "PowerShell · Entra CLI",
        "command": "az ad signed-in-user show --query '{id:id,userPrincipalName:userPrincipalName}'",
        "lookFor": "Identidad autenticada en CLI; revisar MFA en políticas del portal/Graph."
      },
      {
        "platform": "Linux · SSH",
        "command": "sshd -T | grep -Ei 'authenticationmethods|kbdinteractiveauthentication|passwordauthentication'",
        "lookFor": "Configuración efectiva del demonio SSH (ejecutar en servidor autorizado)."
      }
    ]
  },
  {
    "id": "term-6",
    "symptom": "Persisten administradores locales o privilegios excesivos.",
    "verify": "Enumera grupos y eleva la revisión a permisos efectivos por recurso.",
    "interpret": "Una membresía privilegiada requiere justificación y propietario.",
    "commands": [
      {
        "platform": "Linux",
        "command": "id; getent group sudo; getent group wheel",
        "lookFor": "Grupos del usuario y miembros de grupos administrativos presentes."
      },
      {
        "platform": "PowerShell",
        "command": "Get-LocalGroup | Where-Object SID -eq 'S-1-5-32-544' | Get-LocalGroupMember",
        "lookFor": "Miembros del grupo Administradores, independiente del idioma del sistema."
      }
    ]
  },
  {
    "id": "term-7",
    "symptom": "Un escáner marca una CVE sin confirmar afectación.",
    "verify": "Recoge versión real, características habilitadas y boletín oficial.",
    "interpret": "Una coincidencia de versión no basta para confirmar vulnerabilidad.",
    "commands": [
      {
        "platform": "Linux · Debian",
        "command": "dpkg-query -W -f='${Package} ${Version}\\n' openssl",
        "lookFor": "Versión instalada; consultar backports y avisos del proveedor."
      },
      {
        "platform": "PowerShell",
        "command": "Get-ComputerInfo | Select-Object WindowsProductName,OsVersion,OsBuildNumber",
        "lookFor": "Producto y compilación; contrasta con avisos de seguridad aplicables."
      }
    ]
  },
  {
    "id": "term-9",
    "symptom": "Un sistema parece fuera de soporte pero hay soporte extendido.",
    "verify": "Identifica versión exacta y edición; solicita contrato o canal de mantenimiento.",
    "interpret": "No declares EOL sin confirmar producto, release y condiciones contractuales.",
    "commands": [
      {
        "platform": "Linux",
        "command": "cat /etc/os-release",
        "lookFor": "ID, versión y nombre completo de la distribución."
      },
      {
        "platform": "PowerShell",
        "command": "Get-ComputerInfo | Select-Object WindowsProductName,WindowsVersion,OsBuildNumber",
        "lookFor": "Versión y build del equipo auditado."
      }
    ]
  },
  {
    "id": "term-10",
    "symptom": "El EDR aparece desplegado pero el agente no reporta.",
    "verify": "Consulta estado local y última telemetría en consola central.",
    "interpret": "Proceso activo no equivale a protección funcional.",
    "commands": [
      {
        "platform": "Linux",
        "command": "systemctl --type=service --state=running",
        "lookFor": "Servicios activos; identifica el agente por producto."
      },
      {
        "platform": "PowerShell",
        "command": "Get-Service | Where-Object Status -eq 'Running' | Select-Object Name,DisplayName",
        "lookFor": "Servicios en ejecución; validar salud en la consola EDR."
      }
    ]
  },
  {
    "id": "term-11",
    "symptom": "Existen servicios y opciones no alineados con la línea base.",
    "verify": "Compara ajustes reales frente a benchmark aplicable y excepciones aprobadas.",
    "interpret": "Un endurecimiento aislado puede causar incompatibilidades; no apliques cambios durante la verificación.",
    "commands": [
      {
        "platform": "Linux",
        "command": "systemctl list-unit-files --state=enabled --type=service",
        "lookFor": "Servicios configurados para arrancar."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction",
        "lookFor": "Postura del firewall local por perfil."
      }
    ]
  },
  {
    "id": "term-14",
    "symptom": "Una regla parece demasiado amplia o nunca se utiliza.",
    "verify": "Revisa origen, destino, acción, orden, ámbito y contadores en el firewall responsable.",
    "interpret": "No cambies políticas para probar: una ausencia de logs tampoco demuestra bloqueo.",
    "commands": [
      {
        "platform": "Linux · nftables",
        "command": "sudo nft list ruleset",
        "lookFor": "Reglas efectivas; la lectura suele requerir permisos de administrador."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetFirewallRule -PolicyStore ActiveStore | Where-Object Enabled -eq 'True' | Select-Object DisplayName,Direction,Action",
        "lookFor": "Reglas de Windows activas; revisar filtros y políticas de red por separado."
      }
    ]
  },
  {
    "id": "term-15",
    "symptom": "Dos copias de una evidencia tienen huellas distintas.",
    "verify": "Calcula SHA-256 del original y de la copia sin modificar ninguno.",
    "interpret": "Hashes distintos indican contenido diferente, no prueban el motivo del cambio.",
    "commands": [
      {
        "platform": "Linux",
        "command": "sha256sum '/ruta/evidencia.bin'",
        "lookFor": "Huella SHA-256 del archivo indicado."
      },
      {
        "platform": "PowerShell",
        "command": "Get-FileHash -Algorithm SHA256 -Path 'C:\\Ruta\\evidencia.bin'",
        "lookFor": "Hash SHA-256; cotejar con la cadena de custodia."
      }
    ]
  },
  {
    "id": "term-18",
    "symptom": "Una publicación NAT permite tráfico inesperado.",
    "verify": "Contrasta tablas NAT con las reglas de filtrado aplicadas.",
    "interpret": "La traducción de direcciones no actúa como control de autorización.",
    "commands": [
      {
        "platform": "Linux",
        "command": "sudo nft list ruleset",
        "lookFor": "Busca reglas de dnat/snat y políticas de filtrado."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetNat | Format-Table Name,InternalIPInterfaceAddressPrefix",
        "lookFor": "NAT configurado en Windows; puede no existir en el host auditado."
      }
    ]
  },
  {
    "id": "term-19",
    "symptom": "Una VPN se conecta, pero no accede a recursos o usa rutas excesivas.",
    "verify": "Verifica interfaz, rutas asignadas, DNS y control de acceso.",
    "interpret": "Estar conectado a la VPN no garantiza segmentación correcta.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ip route show",
        "lookFor": "Rutas instaladas con el túnel conectado."
      },
      {
        "platform": "PowerShell",
        "command": "Get-VpnConnection | Select-Object Name,ServerAddress,SplitTunneling,ConnectionStatus",
        "lookFor": "Configuración VPN del usuario; consulta -AllUserConnection si procede."
      }
    ]
  },
  {
    "id": "term-21",
    "symptom": "Hay conflictos de direcciones o tráfico enviado al gateway erróneo.",
    "verify": "Revisa prefijos en todos los interfaces y la tabla de rutas.",
    "interpret": "Una máscara equivocada puede originar accesos fallidos o rutas amplias.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ip -br -4 addr",
        "lookFor": "Direcciones y prefijos IPv4 por interfaz."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetIPConfiguration",
        "lookFor": "Interfaces, gateway y servidores DNS reportados."
      }
    ]
  },
  {
    "id": "term-22",
    "symptom": "Se aplica una denegación pese a existir una regla permitida.",
    "verify": "Contrasta orden y prioridad de ACL en el dispositivo responsable.",
    "interpret": "Un permiso mostrado no garantiza coincidencia o precedencia.",
    "commands": [
      {
        "platform": "Linux",
        "command": "sudo nft -a list ruleset",
        "lookFor": "Reglas y handles de nftables; requiere lectura privilegiada."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetFirewallRule -PolicyStore ActiveStore | Select-Object DisplayName,Direction,Action,Enabled",
        "lookFor": "Inventario local de reglas (no sustituye revisión de ACL en switch/firewall)."
      }
    ]
  },
  {
    "id": "term-24",
    "symptom": "Un puerto con NAC no pide credenciales o recibe VLAN incorrecta.",
    "verify": "Consulta sesiones de autenticación en switch y cliente.",
    "interpret": "Un puerto excepcional debe documentarse; el estado del cliente no prueba política del switch.",
    "commands": [
      {
        "platform": "Windows · CMD",
        "command": "netsh lan show interfaces",
        "lookFor": "Interfaces LAN y estado 802.1X cuando lo soporta el adaptador."
      },
      {
        "platform": "Linux",
        "command": "nmcli -f GENERAL,802-1X connection show",
        "lookFor": "Propiedades 802.1X de NetworkManager; depende de conexiones configuradas."
      }
    ]
  },
  {
    "id": "term-25",
    "symptom": "El nombre resuelve a IP diferente según origen o aparecen fallos intermitentes.",
    "verify": "Compara resolutores, respuestas A/AAAA y TTL entre red interna y externa.",
    "interpret": "Respuestas divergentes pueden ser split DNS legítimo; registra servidor consultado.",
    "commands": [
      {
        "platform": "Linux · dig",
        "command": "dig servidor.autorizado.invalid A",
        "lookFor": "Respuesta, TTL y servidor DNS consultado; reemplaza el nombre."
      },
      {
        "platform": "PowerShell",
        "command": "Resolve-DnsName servidor.autorizado.invalid -Type A",
        "lookFor": "Registros A y servidor usado; reemplaza el nombre."
      },
      {
        "platform": "Linux",
        "command": "resolvectl status",
        "lookFor": "Resolutores efectivos por enlace en sistemas con systemd-resolved."
      }
    ]
  },
  {
    "id": "term-26",
    "symptom": "Los equipos reciben DNS, gateway o rango IP incorrectos.",
    "verify": "Contrasta arrendamiento efectivo con opciones del servidor DHCP.",
    "interpret": "Un cliente no revela por sí solo si existe un servidor DHCP rogue.",
    "commands": [
      {
        "platform": "Linux",
        "command": "nmcli -f IP4,GENERAL device show",
        "lookFor": "Dirección IP, puerta de enlace y DNS según NetworkManager."
      },
      {
        "platform": "PowerShell",
        "command": "Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object DHCPEnabled | Select-Object Description,DHCPServer,IPAddress",
        "lookFor": "Servidor DHCP anunciado y direcciones en adaptadores con DHCP."
      }
    ]
  },
  {
    "id": "term-27",
    "symptom": "La MAC del gateway cambia repetidamente sin mantenimiento previsto.",
    "verify": "Correlaciona vecinos ARP con inventario y telemetría del switch.",
    "interpret": "Cambios ARP no son prueba aislada de suplantación.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ip neigh show",
        "lookFor": "Asociaciones IP–MAC y su estado."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetNeighbor -AddressFamily IPv4 | Select-Object IPAddress,LinkLayerAddress,State",
        "lookFor": "Entradas ARP/vecinos observadas localmente."
      }
    ]
  },
  {
    "id": "term-28",
    "symptom": "SSH/RDP está escuchando en interfaces no previstas.",
    "verify": "Valida listeners locales y comprueba la exposición solo desde segmentos autorizados.",
    "interpret": "Puerto escuchando no significa accesibilidad desde Internet.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ss -lntp",
        "lookFor": "TCP en escucha y procesos; algunos PID precisan privilegios."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetTCPConnection -State Listen | Sort-Object LocalPort",
        "lookFor": "Dirección y puerto de escuchas TCP."
      },
      {
        "platform": "PowerShell · red",
        "command": "Test-NetConnection -ComputerName servidor.autorizado.invalid -Port 3389",
        "lookFor": "Prueba activa de conectividad RDP: solo en alcance autorizado."
      }
    ]
  },
  {
    "id": "term-29",
    "symptom": "Un servicio negocia TLS antiguo o tiene errores de validación.",
    "verify": "Inspecciona certificado, hostname y protocolo sin desactivar verificación.",
    "interpret": "La prueba de un endpoint no cubre el resto de servicios TLS.",
    "commands": [
      {
        "platform": "OpenSSL · red",
        "command": "openssl s_client -connect servidor.autorizado.invalid:443 -servername servidor.autorizado.invalid </dev/null",
        "lookFor": "Certificado y versión TLS; conexión a extremo autorizado."
      },
      {
        "platform": "curl · red",
        "command": "curl -Iv https://servidor.autorizado.invalid",
        "lookFor": "Handshake y validación; no uses -k para ocultar errores de confianza."
      }
    ]
  },
  {
    "id": "term-30",
    "symptom": "Un certificado caduca o no coincide con el nombre del host.",
    "verify": "Revisa subjectAltName, issuer, fechas, cadena y renovación.",
    "interpret": "Un certificado vigente puede ser inválido para el nombre o la cadena.",
    "commands": [
      {
        "platform": "OpenSSL · archivo",
        "command": "openssl x509 -in '/ruta/certificado.pem' -noout -subject -issuer -dates -ext subjectAltName",
        "lookFor": "Identidad, emisor, validez y SAN sin exponer clave privada."
      },
      {
        "platform": "PowerShell",
        "command": "Get-ChildItem Cert:\\LocalMachine\\My | Select-Object Subject,Issuer,NotAfter,Thumbprint",
        "lookFor": "Certificados del almacén personal de equipo."
      }
    ]
  },
  {
    "id": "term-31",
    "symptom": "Un cliente se asocia pero la red Wi-Fi tiene protección débil.",
    "verify": "Contrasta método de autenticación, cifrado y perfil con configuración del punto de acceso.",
    "interpret": "El perfil cliente no demuestra aislamiento ni claves adecuadas de toda la WLAN.",
    "commands": [
      {
        "platform": "Windows · CMD",
        "command": "netsh wlan show interfaces",
        "lookFor": "SSID, tipo de autenticación y cifrado de conexión actual."
      },
      {
        "platform": "Linux",
        "command": "nmcli -f IN-USE,SSID,SECURITY,SIGNAL dev wifi list",
        "lookFor": "Seguridad anunciada de redes visibles; no valida políticas del controlador."
      }
    ]
  },
  {
    "id": "term-32",
    "symptom": "Los invitados pueden resolver o alcanzar recursos internos.",
    "verify": "Comprueba rutas, DNS y políticas con pruebas explícitamente autorizadas.",
    "interpret": "La respuesta DNS interna no equivale a acceso permitido al servicio.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ip route",
        "lookFor": "Rutas visibles desde el equipo invitado."
      },
      {
        "platform": "PowerShell · red",
        "command": "Test-NetConnection -ComputerName servidor.autorizado.invalid -Port 443",
        "lookFor": "Acceso al puerto aprobado; registrar origen, destino y resultado."
      }
    ]
  },
  {
    "id": "term-34",
    "symptom": "Inventario y consola de parches discrepan.",
    "verify": "Revisa fecha, paquetes instalados, reinicio pendiente y fuente de actualización.",
    "interpret": "Un parche pendiente no siempre equivale a CVE explotable: comprueba el boletín.",
    "commands": [
      {
        "platform": "Linux · Debian",
        "command": "apt list --upgradable",
        "lookFor": "Paquetes actualizables según índices disponibles; no instala nada."
      },
      {
        "platform": "PowerShell",
        "command": "Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 20",
        "lookFor": "Actualizaciones registradas por Windows; no cubre todo el software."
      }
    ]
  },
  {
    "id": "term-36",
    "symptom": "Un puerto aparece abierto sin propietario técnico.",
    "verify": "Relaciona socket con proceso, unidad y justificación de negocio.",
    "interpret": "No clasifiques exposición externa solo con inspección local.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ss -lntup",
        "lookFor": "Sockets TCP/UDP en escucha, PID cuando sea visible."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetTCPConnection -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess",
        "lookFor": "Puerto, dirección y PID en escucha."
      }
    ]
  },
  {
    "id": "term-38",
    "symptom": "El arranque seguro figura habilitado solo en documentación.",
    "verify": "Consulta estado UEFI/firmware y registra excepciones.",
    "interpret": "La presencia de UEFI no prueba Secure Boot activo.",
    "commands": [
      {
        "platform": "Linux",
        "command": "mokutil --sb-state",
        "lookFor": "Estado Secure Boot (requiere mokutil y arranque EFI)."
      },
      {
        "platform": "PowerShell",
        "command": "Confirm-SecureBootUEFI",
        "lookFor": "True/False en hardware UEFI compatible; puede requerir elevación."
      }
    ]
  },
  {
    "id": "term-39",
    "symptom": "El TPM no está disponible para cifrado o atestación.",
    "verify": "Contrasta disponibilidad, versión y estado de aprovisionamiento.",
    "interpret": "Un TPM presente puede estar deshabilitado o sin inicializar.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ls -l /dev/tpm*",
        "lookFor": "Dispositivos TPM expuestos por el sistema, si existen."
      },
      {
        "platform": "PowerShell",
        "command": "Get-Tpm",
        "lookFor": "Presencia, activación y estado de preparación del TPM."
      }
    ]
  },
  {
    "id": "term-40",
    "symptom": "Una unidad con datos sensibles no muestra cifrado efectivo.",
    "verify": "Revisa estado del volumen y claves bajo custodia; nunca extraigas material secreto.",
    "interpret": "Una partición cifrada no implica que todos los volúmenes lo estén.",
    "commands": [
      {
        "platform": "Linux",
        "command": "lsblk -f",
        "lookFor": "Tipos de sistema de archivos y dispositivos LUKS visibles."
      },
      {
        "platform": "PowerShell",
        "command": "Get-BitLockerVolume | Select-Object MountPoint,VolumeStatus,ProtectionStatus,EncryptionPercentage",
        "lookFor": "Estado de BitLocker por volumen."
      }
    ]
  },
  {
    "id": "term-42",
    "symptom": "El antivirus aparece instalado pero está deshabilitado.",
    "verify": "Valida motor, firmas, protección en tiempo real y exclusiones con consola EPP.",
    "interpret": "No basta con detectar un proceso o producto instalado.",
    "commands": [
      {
        "platform": "PowerShell · Defender",
        "command": "Get-MpComputerStatus | Select-Object AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated",
        "lookFor": "Estado reportado por Microsoft Defender, si se utiliza."
      },
      {
        "platform": "Linux",
        "command": "systemctl --type=service --state=running",
        "lookFor": "Servicios activos; contrastar agente concreto con gestión central."
      }
    ]
  },
  {
    "id": "term-45",
    "symptom": "Se detectan administradores inesperados en el dominio.",
    "verify": "Revisa delegaciones y grupos sensibles desde equipo con RSAT/autorización.",
    "interpret": "Distingue grupos anidados y cuentas de servicio antes de atribuir riesgo.",
    "commands": [
      {
        "platform": "PowerShell · RSAT",
        "command": "Get-ADGroupMember -Identity 'Domain Admins' -Recursive | Select-Object Name,ObjectClass,SamAccountName",
        "lookFor": "Miembros efectivos; requiere módulo ActiveDirectory y privilegios de lectura."
      },
      {
        "platform": "Windows · CMD",
        "command": "whoami /groups",
        "lookFor": "Grupos presentes en el token de la sesión actual."
      }
    ]
  },
  {
    "id": "term-46",
    "symptom": "La política de seguridad no se aplica a un equipo.",
    "verify": "Comprueba OU, filtrado, herencia y resultado efectivo.",
    "interpret": "Una GPO vinculada no garantiza que sus opciones se hayan aplicado.",
    "commands": [
      {
        "platform": "Windows · CMD",
        "command": "gpresult /scope computer /r",
        "lookFor": "GPO de equipo realmente aplicadas y filtradas."
      },
      {
        "platform": "Windows · CMD",
        "command": "gpresult /scope user /r",
        "lookFor": "GPO del usuario de sesión; permisos y contexto influyen."
      }
    ]
  },
  {
    "id": "term-47",
    "symptom": "Hay fallos Kerberos o relojes fuera de sincronía.",
    "verify": "Comprueba tickets del usuario, SPN y sincronización horaria.",
    "interpret": "La ausencia de ticket puede ser normal si no hubo autenticación Kerberos.",
    "commands": [
      {
        "platform": "Windows / Linux",
        "command": "klist",
        "lookFor": "Tickets del contexto actual; la sintaxis disponible depende de la plataforma."
      },
      {
        "platform": "Windows · CMD",
        "command": "w32tm /query /status",
        "lookFor": "Origen y estado horario, relevantes para Kerberos."
      }
    ]
  },
  {
    "id": "term-48",
    "symptom": "Un directorio LDAP se consulta sin cifrado válido.",
    "verify": "Distingue LDAP, LDAPS y StartTLS, y valida la cadena de certificados.",
    "interpret": "Un puerto 636 abierto no demuestra que la aplicación valide el certificado.",
    "commands": [
      {
        "platform": "OpenSSL · red",
        "command": "openssl s_client -connect dc.autorizado.invalid:636 -servername dc.autorizado.invalid </dev/null",
        "lookFor": "Certificado y handshake LDAPS en destino autorizado."
      },
      {
        "platform": "PowerShell · red",
        "command": "Test-NetConnection -ComputerName dc.autorizado.invalid -Port 636",
        "lookFor": "Conectividad TCP; no verifica la seguridad de la autenticación."
      }
    ]
  },
  {
    "id": "term-49",
    "symptom": "Cuentas con acceso administrativo carecen de propietario.",
    "verify": "Cruza membresías, uso real, necesidad y revisiones aprobadas.",
    "interpret": "La existencia de una cuenta no indica actividad ni autorización.",
    "commands": [
      {
        "platform": "Linux",
        "command": "getent group sudo; getent group wheel",
        "lookFor": "Grupos administrativos locales disponibles."
      },
      {
        "platform": "PowerShell",
        "command": "Get-LocalGroup | Where-Object SID -eq 'S-1-5-32-544' | Get-LocalGroupMember",
        "lookFor": "Miembros del grupo de administradores locales."
      }
    ]
  },
  {
    "id": "term-51",
    "symptom": "Una identidad de servicio tiene privilegios excesivos.",
    "verify": "Revisa ejecución efectiva y dueño del servicio sin extraer credenciales.",
    "interpret": "Cuentas técnicas deben tener alcance y rotación justificados.",
    "commands": [
      {
        "platform": "Linux",
        "command": "systemctl show ssh.service -p User -p Group",
        "lookFor": "Usuario/grupo configurados en ejemplo de servicio systemd (ajusta unidad)."
      },
      {
        "platform": "PowerShell",
        "command": "Get-CimInstance Win32_Service | Select-Object Name,StartName,State",
        "lookFor": "Identidades bajo las que se ejecutan los servicios."
      }
    ]
  },
  {
    "id": "term-57",
    "symptom": "La versión identificada por escáner corresponde a otro producto.",
    "verify": "Corrobora producto/edición/versión y CPE normalizado.",
    "interpret": "Un CPE sugerido no constituye identificación fiable del software.",
    "commands": [
      {
        "platform": "Linux",
        "command": "cat /etc/os-release; uname -r",
        "lookFor": "Identidad del SO y kernel."
      },
      {
        "platform": "PowerShell",
        "command": "Get-ComputerInfo | Select-Object WindowsProductName,OsBuildNumber",
        "lookFor": "Producto y build reportados por Windows."
      }
    ]
  },
  {
    "id": "term-62",
    "symptom": "Se desconoce qué procesos atienden conexiones.",
    "verify": "Enumera listeners y distingue interfaz local de exposición remota.",
    "interpret": "Inventario de puertos locales no sustituye la evaluación perimetral.",
    "commands": [
      {
        "platform": "Linux",
        "command": "ss -lntup",
        "lookFor": "Servicios TCP/UDP en escucha y procesos visibles."
      },
      {
        "platform": "PowerShell",
        "command": "Get-NetTCPConnection -State Listen",
        "lookFor": "Puertos de escucha TCP por interfaz."
      }
    ]
  },
  {
    "id": "term-64",
    "symptom": "El catálogo muestra backups, pero faltan puntos esperados.",
    "verify": "Consulta el histórico de ejecuciones y retención configurada.",
    "interpret": "Una copia existente no demuestra restaurabilidad.",
    "commands": [
      {
        "platform": "Linux · restic",
        "command": "restic snapshots",
        "lookFor": "Snapshots disponibles en repositorio ya configurado; requiere acceso de lectura."
      },
      {
        "platform": "PowerShell · Windows Backup",
        "command": "Get-WBSummary",
        "lookFor": "Resumen de Windows Server Backup si el componente está disponible."
      }
    ]
  },
  {
    "id": "term-67",
    "symptom": "No se dispone de evidencia de restauraciones.",
    "verify": "Busca resultados de simulacros y verifica checksums sin sobrescribir producción.",
    "interpret": "No ejecutes restauraciones ni montajes de producción durante una comprobación documental.",
    "commands": [
      {
        "platform": "Linux · restic",
        "command": "restic snapshots",
        "lookFor": "Inventario de puntos de restauración (no realiza restauración)."
      },
      {
        "platform": "PowerShell · Windows Backup",
        "command": "Get-WBSummary",
        "lookFor": "Resultado resumido de operaciones anteriores, si se instaló el módulo."
      }
    ]
  },
  {
    "id": "term-72",
    "symptom": "El archivo recibido difiere del registrado en el acta.",
    "verify": "Repite hash sobre copia preservada y contrasta hora y custodios.",
    "interpret": "La coincidencia de hash apoya integridad, no acredita autoría.",
    "commands": [
      {
        "platform": "Linux",
        "command": "sha256sum '/ruta/evidencia.bin'",
        "lookFor": "Calcula huella sin escribir sobre el archivo."
      },
      {
        "platform": "PowerShell",
        "command": "Get-FileHash -Path 'C:\\Ruta\\evidencia.bin' -Algorithm SHA256",
        "lookFor": "Hash reproducible para anexar a la evidencia."
      }
    ]
  },
  {
    "id": "term-87",
    "symptom": "Los permisos efectivos cloud exceden los documentados.",
    "verify": "Identifica la sesión activa y enumera permisos del recurso aprobado.",
    "interpret": "Credenciales CLI pueden tener acceso amplio; protege la salida y evita enumeraciones fuera de alcance.",
    "commands": [
      {
        "platform": "AWS CLI",
        "command": "aws sts get-caller-identity",
        "lookFor": "Identidad y cuenta de la sesión actual; la salida contiene identificadores."
      },
      {
        "platform": "Azure CLI",
        "command": "az account show --query '{name:name,id:id,tenantId:tenantId}'",
        "lookFor": "Suscripción y tenant activos; datos sensibles del cliente."
      }
    ]
  },
  {
    "id": "term-88",
    "symptom": "Un bucket podría permitir exposición pública.",
    "verify": "Valida configuración de bloqueo público y políticas en el recurso autorizado.",
    "interpret": "La falta de PublicAccessBlock no implica publicación automática; revisar política y ACL.",
    "commands": [
      {
        "platform": "AWS CLI",
        "command": "aws s3api get-public-access-block --bucket NOMBRE_BUCKET",
        "lookFor": "Configuración Block Public Access; requiere permisos s3:GetBucketPublicAccessBlock."
      },
      {
        "platform": "AWS CLI",
        "command": "aws s3api get-bucket-policy-status --bucket NOMBRE_BUCKET",
        "lookFor": "IsPublic según evaluación de política; no sustituye otras comprobaciones."
      }
    ]
  },
  {
    "id": "term-90",
    "symptom": "Un contenedor publica puertos o ejecuta imágenes no aprobadas.",
    "verify": "Consulta inventario de contenedores y bindings sin inspeccionar variables secretas.",
    "interpret": "Exposición de puertos debe evaluarse junto con firewall y red del host.",
    "commands": [
      {
        "platform": "Docker",
        "command": "docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Ports}}'",
        "lookFor": "Nombre, imagen y publicación de puertos; acceso al socket Docker es privilegiado."
      },
      {
        "platform": "Docker",
        "command": "docker image ls --format 'table {{.Repository}}\\t{{.Tag}}\\t{{.ID}}'",
        "lookFor": "Imágenes locales; validar procedencia y digest por política."
      }
    ]
  },
  {
    "id": "term-91",
    "symptom": "Cargas Kubernetes se ejecutan sin políticas de red.",
    "verify": "Consulta namespaces, pods y NetworkPolicy con un rol autorizado.",
    "interpret": "La presencia de NetworkPolicy no asegura aplicación: depende del CNI.",
    "commands": [
      {
        "platform": "Kubernetes CLI",
        "command": "kubectl get networkpolicies --all-namespaces",
        "lookFor": "Políticas existentes por namespace; requiere permisos de lectura."
      },
      {
        "platform": "Kubernetes CLI",
        "command": "kubectl auth can-i --list",
        "lookFor": "Permisos concedidos a la identidad actual; puede mostrar recursos sensibles."
      }
    ]
  },
  {
    "id": "term-94",
    "symptom": "Se confunde cifrado del disco con cifrado de datos de aplicación.",
    "verify": "Inspecciona volúmenes protegidos y límites del mecanismo.",
    "interpret": "El cifrado en reposo no sustituye permisos y gestión de claves.",
    "commands": [
      {
        "platform": "Linux",
        "command": "lsblk -f",
        "lookFor": "Dispositivos cifrados identificables por FSTYPE."
      },
      {
        "platform": "PowerShell",
        "command": "Get-BitLockerVolume | Select-Object MountPoint,ProtectionStatus,VolumeStatus",
        "lookFor": "Volúmenes BitLocker y estado de protección."
      }
    ]
  },
  {
    "id": "term-96",
    "symptom": "Un usuario consulta recursos que no pertenecen a su rol.",
    "verify": "Comprueba grupos, ACL locales y políticas aplicadas sin cambiar permisos.",
    "interpret": "Los permisos del sistema de archivos no representan todos los controles de aplicación.",
    "commands": [
      {
        "platform": "Linux",
        "command": "namei -l '/ruta/recurso'",
        "lookFor": "Permisos y propietarios a lo largo de la ruta."
      },
      {
        "platform": "PowerShell",
        "command": "Get-Acl -Path 'C:\\Ruta\\Recurso' | Select-Object -ExpandProperty Access",
        "lookFor": "Entradas ACL para el recurso elegido."
      }
    ]
  },
  {
    "id": "term-97",
    "symptom": "Se reciben menos eventos en el SIEM de los esperados.",
    "verify": "Comprueba generación y entrega de logs en el origen, desfase temporal y filtros.",
    "interpret": "Tener agentes instalados no prueba ingestión ni correlación.",
    "commands": [
      {
        "platform": "Linux",
        "command": "journalctl --since '1 hour ago' -p warning --no-pager",
        "lookFor": "Eventos recientes de severidad warning o superior."
      },
      {
        "platform": "PowerShell",
        "command": "Get-WinEvent -ListLog Security | Select-Object LogName,RecordCount,IsEnabled",
        "lookFor": "Estado y volumen del registro Security (requiere permisos)."
      }
    ]
  },
  {
    "id": "term-99",
    "symptom": "Faltan eventos relevantes o la retención es insuficiente.",
    "verify": "Comprueba política de auditoría, tamaño y filtros de logs.",
    "interpret": "Ausencia de registro no prueba ausencia de actividad.",
    "commands": [
      {
        "platform": "Windows · CMD",
        "command": "auditpol /get /category:*",
        "lookFor": "Subcategorías de auditoría de Windows y su estado."
      },
      {
        "platform": "Linux",
        "command": "journalctl --disk-usage",
        "lookFor": "Uso estimado del journal; consulta configuración de retención por separado."
      }
    ]
  },
  {
    "id": "term-100",
    "symptom": "Marcas temporales entre equipos no coinciden.",
    "verify": "Consulta fuente, estado y desfase NTP sin cambiar configuración.",
    "interpret": "Para incidentes registra zona horaria, offset y hora de captura.",
    "commands": [
      {
        "platform": "Linux",
        "command": "timedatectl status",
        "lookFor": "Estado NTP y sincronización local en sistemas systemd."
      },
      {
        "platform": "Linux · chrony",
        "command": "chronyc tracking",
        "lookFor": "Referencia, offset y dispersión si usa chrony."
      },
      {
        "platform": "Windows · CMD",
        "command": "w32tm /query /status",
        "lookFor": "Origen y estado de sincronización de hora Windows."
      }
    ]
  },
  {
    "id": "term-101",
    "symptom": "Se sospecha un patrón de fallos de autenticación.",
    "verify": "Filtra eventos por ventana y contrasta usuarios, origen y procesos esperados.",
    "interpret": "Repeticiones pueden deberse a errores operativos; no atribuyas incidente sin contexto.",
    "commands": [
      {
        "platform": "PowerShell",
        "command": "Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625;StartTime=(Get-Date).AddHours(-2)} -MaxEvents 50",
        "lookFor": "Fallos de inicio de sesión Windows; contiene datos personales."
      },
      {
        "platform": "Linux",
        "command": "journalctl --since '2 hours ago' --no-pager | grep -Ei 'authentication failure|failed password'",
        "lookFor": "Patrones de autenticación fallida; proteger resultados."
      }
    ]
  },
  {
    "id": "term-104",
    "symptom": "Hay actividad de cifrado sospechosa o borrado de copias.",
    "verify": "Correlaciona alertas EDR, cambios de archivos, cuentas y copias protegidas.",
    "interpret": "No ejecutes muestras, detengas servicios ni alteres evidencias desde esta guía.",
    "commands": [
      {
        "platform": "Windows · CMD",
        "command": "vssadmin list shadows",
        "lookFor": "Puntos de sombra visibles; su ausencia no prueba ataque."
      },
      {
        "platform": "Linux",
        "command": "journalctl --since '1 hour ago' -p warning --no-pager",
        "lookFor": "Avisos recientes para correlacionar con telemetría EDR y almacenamiento."
      }
    ]
  }
].map(({id,...guide})=>[id,Object.freeze(guide)])));
 const MAC_COMMANDS=[{"id":"term-25","platform":"macOS","command":"scutil --dns","lookFor":"Resolutores DNS efectivos por interfaz y orden de búsqueda."},{"id":"term-28","platform":"macOS","command":"lsof -nP -iTCP -sTCP:LISTEN","lookFor":"Procesos y puertos TCP en escucha (privilegios según proceso)."},{"id":"term-29","platform":"macOS","command":"curl -Iv https://servidor.autorizado.invalid","lookFor":"Validación TLS y respuesta de cabeceras del host aprobado."},{"id":"term-30","platform":"macOS","command":"security find-certificate -a -p /Library/Keychains/System.keychain","lookFor":"Certificados públicos del llavero del sistema; no extrae claves privadas."},{"id":"term-40","platform":"macOS","command":"fdesetup status","lookFor":"Estado FileVault del volumen de arranque; puede requerir permisos."},{"id":"term-15","platform":"macOS","command":"shasum -a 256 '/ruta/evidencia.bin'","lookFor":"SHA-256 reproducible de evidencia."},{"id":"term-72","platform":"macOS","command":"shasum -a 256 '/ruta/evidencia.bin'","lookFor":"Comprueba integridad en una copia preservada."},{"id":"term-100","platform":"macOS","command":"systemsetup -getusingnetworktime; systemsetup -getnetworktimeserver","lookFor":"Estado/configuración NTP; ciertos datos requieren privilegios."},{"id":"term-36","platform":"macOS","command":"lsof -nP -iTCP -sTCP:LISTEN","lookFor":"Servicios en escucha."},{"id":"term-21","platform":"macOS","command":"ifconfig; netstat -rn -f inet","lookFor":"Direcciones/prefijos y rutas IPv4."},{"id":"term-19","platform":"macOS","command":"scutil --nwi; netstat -rn -f inet","lookFor":"Contexto de interfaces y rutas para VPN."},{"id":"term-34","platform":"macOS","command":"softwareupdate --list","lookFor":"Actualizaciones ofrecidas al host; no instala actualizaciones."},{"id":"term-99","platform":"macOS","command":"log show --last 1h --style compact --predicate 'messageType == error'","lookFor":"Errores recientes; filtra sin guardar datos personales innecesarios."},{"id":"term-101","platform":"macOS","command":"log show --last 1h --style compact --predicate 'process == \"sshd\"'","lookFor":"Eventos recientes del servicio SSH cuando existan."},{"id":"term-26","platform":"macOS","command":"ipconfig getpacket en0","lookFor":"Parámetros DHCP de en0; comprobar interfaz activa."},{"id":"term-31","platform":"macOS","command":"system_profiler SPAirPortDataType","lookFor":"Seguridad y configuración Wi-Fi visible desde el cliente."},{"id":"term-42","platform":"macOS","command":"systemextensionsctl list","lookFor":"Extensiones de sistema presentes; verificar estado EDR en consola del fabricante."},{"id":"term-39","platform":"macOS","command":"system_profiler SPiBridgeDataType","lookFor":"Componentes de seguridad disponibles según hardware Apple (no implica TPM)."}];
 for(const entry of MAC_COMMANDS){const g=GUIDES[entry.id];if(g)g.commands.push({platform:entry.platform,command:entry.command,lookFor:entry.lookFor});}
 const CATEGORIES=Object.freeze([...new Set(TERMS.map(t=>t.category))]);
 const normalize = input=>String(input??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('es').trim();
 const byId=id=>TERMS.find(t=>t.id===id)||null;
 const search=(query='',category='Todas')=>{
  const tokens=normalize(query).split(/\s+/).filter(Boolean);
  return TERMS.filter(t=>{
   if(category!=='Todas'&&t.category!==category)return false;
   if(!tokens.length)return true;
   const guide=GUIDES[t.id];
   const haystack=normalize([t.title,t.category,t.description,t.check,t.why,t.example,t.fullName,...Object.values(t.help||{}),...(t.references||[]).map(x=>x.label),...(t.aliases||[]),guide?.symptom,guide?.verify,guide?.interpret,...(guide?.commands||[]).flatMap(c=>[c.platform,c.command,c.lookFor])].join(' '));
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
 globalThis.AuditGlossary=Object.freeze({TERMS,CATEGORIES,GUIDES,search,byId,normalize});
})();
