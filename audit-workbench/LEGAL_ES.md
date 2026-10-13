# Cláusulas modelo para una auditoría realizada en España

**Documento informativo, no asesoramiento jurídico**. Las cláusulas de Audit Workbench son modelos iniciales para la redacción técnica del informe, no un contrato de auditoría, autorización de pentesting, NDA, acuerdo de encargo de tratamiento, póliza ni renuncia general válida de responsabilidad. El auditor debe revisar cada texto con el cliente y, cuando corresponda, con asesoría jurídica.

## Referencias normativas generales (contrastadas octubre de 2026)

- **Reglamento (UE) 2016/679 (RGPD)**: artículo 5 (principios del tratamiento), artículo 28 (encargado del tratamiento cuando proceda), artículo 32 (seguridad), artículos 33 y 34 (brechas, según las circunstancias). https://eur-lex.europa.eu/legal-content/ES/ALL/?uri=celex%3A32016R0679
- **Ley Orgánica 3/2018 (LOPDGDD)**: adaptación/complemento del RGPD en España. https://www.boe.es/eli/es/lo/2018/12/05/3/con
- **AEPD**: el acuerdo entre responsable y encargado se formaliza cuando la relación y tratamiento así lo requieren, con requisitos específicos; la mera plantilla del informe no lo sustituye. https://www.aepd.es/preguntas-frecuentes/2-tus-obligaciones-como-responsable-del-tratamiento/8-responsable-y-encargado-del-tratamiento/FAQ-0238-cual-seria-el-contenido-del-contrato-de-encargo-de-tratamiento
- **Ley 34/2002 (LSSI-CE)**: contiene previsiones sobre comunicaciones comerciales electrónicas; la entrega profesional de informes por correo no es por sí misma publicidad. No asumir por ello que enviar información confidencial por correo es seguro o contractualmente autorizado. https://www.boe.es/eli/es/l/2002/07/11/34/con

La normativa sectorial adicional dependerá de la organización evaluada (sector público, proveedores de servicios esenciales, operadores críticos, empresas financieras, sector sanitario, etc.). El asistente no declara por defecto cumplimiento ENS, NIS2, DORA, ISO 27001 ni CIS. El alcance, evidencias, requisitos, interpretación aplicable y evaluación jurídica son necesarios antes de efectuar esas afirmaciones.

## Qué deben reflejar el contrato y el informe

1. **Quién autoriza:** identificación de la persona facultada, alcance exacto por activos/redes/sedes, fecha de inicio/fin, ventanas, contactos y reglas de compromiso; quién responde ante incidentes durante la prueba.
2. **Qué no se evalúa:** exclusiones y restricciones, métodos no permitidos, dependencias/terceros, riesgos inherentes y naturaleza temporal de los resultados.
3. **Tratamiento de datos:** roles de las partes, tipología de datos, finalidad, retención, acceso, medidas técnicas y organizativas, subencargados, transferencias internacionales y contratos/documentación exigibles.
4. **Custodia:** dónde se conservan los originales y el JSON, cifrado, acceso limitado, canales de entrega y devoluciones/eliminación pactadas.
5. **Hallazgos e interpretaciones:** evidencias que sustentan el riesgo, controles no verificados, falsos positivos/limitaciones, responsables, riesgo residual, revisión editorial antes de la entrega y firma.
6. **Incidentes y comunicación:** contactos y procedimiento acordados para un incidente detectado durante la auditoría, sin confundirlos con las obligaciones legales de notificación que puedan corresponder a cada parte.

## Reglas para usar las plantillas en la aplicación

En **Cláusulas y privacidad** se pueden editar siete párrafos independientes. La aplicación los incluye en el informe PDF, pero **no indica que estén aprobados por el cliente**. Modifícalos antes de cada auditoría. No utilices cláusulas genéricas para intentar eximir de responsabilidad por dolo, negligencia o incumplimientos legales. En particular, la confidencialidad no autoriza por sí sola a tratar datos personales o a explotar equipos.

Los textos predeterminados se adjuntan al expediente y se conservan en el backup. Si el cliente ha aprobado un documento de autorización o un contrato, consigna su referencia en el alcance y custodia el original por separado; no es recomendable almacenar firmas, claves o documentos originales sensibles dentro del JSON sin cifrado.
