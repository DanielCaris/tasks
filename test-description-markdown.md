# Título principal (H1)

Este es el **título de nivel 1** y debería verse como el encabezado más grande de la jerarquía. Sirve para introducir secciones principales del documento.

## Subtítulo de segundo nivel (H2)

El **H2** se usa para dividir el contenido en bloques lógicos. Aquí podemos incluir texto con *cursiva* y **negrita** combinados, o incluso ***negrita y cursiva*** en la misma frase.

### Título de tercer nivel (H3)

Los encabezados H3 son útiles para subsecciones. Por ejemplo, podemos hablar de `código inline` dentro del texto o de [enlaces a recursos externos](https://www.atlassian.com).

#### Título de cuarto nivel (H4)

El H4 permite una jerarquía más profunda. Aquí podemos incluir:
- Listas con viñetas
- Múltiples elementos
- Para ver el espaciado y la indentación

##### Título de quinto nivel (H5)

El H5 es el penúltimo nivel de encabezado. Útil para secciones muy específicas como *notas técnicas* o **advertencias importantes**.

###### Título de sexto nivel (H6)

El H6 es el nivel más pequeño. Ideal para etiquetas o categorías secundarias dentro de un bloque.

---

## Formato de texto inline

Texto normal, **negrita con asteriscos**, __negrita con guiones bajos__, *cursiva con asterisco*, _cursiva con guión bajo_, y `código inline` para nombres de variables o comandos.

Combinaciones: ***todo en negrita y cursiva***, texto con **negrita** y *cursiva* separados, o un enlace como [Documentación de Jira](https://support.atlassian.com/jira).

---

## Listas

### Lista con viñetas

- Primer elemento de la lista
- Segundo elemento con **texto en negrita**
- Tercer elemento con *cursiva*
- Cuarto elemento con `código` y [enlace](https://example.com)

### Lista numerada

1. Primer paso del proceso
2. Segundo paso con formato **importante**
3. Tercer paso con *énfasis*
4. Cuarto y último paso

### Lista de tareas (checkboxes)

- [ ] Tarea pendiente número uno
- [ ] Tarea pendiente número dos
- [x] Tarea completada
- [x] Otra tarea completada
- [ ] Última tarea pendiente

---

## Citas (blockquote)

> Esta es una cita de bloque. Se usa para destacar citas textuales, notas importantes o contexto adicional que proviene de otra fuente.
>
> Las citas pueden tener **múltiples párrafos** y formato *inline*.

> Otra cita separada para probar el espaciado entre bloques.

---

## Bloques de código

Código inline: `const x = 42` o `function hello() { return "world"; }`

Bloque de código con sintaxis:

```swift
func greet(name: String) -> String {
    return "Hola, \(name)!"
}
print(greet(name: "Mundo"))
```

Bloque sin lenguaje especificado:

```
Este es un bloque de código plano.
Puede contener múltiples líneas.
Útil para logs o salidas de terminal.
```

---

## Enlaces e imágenes

Enlace simple: [Atlassian](https://www.atlassian.com)

Enlace con texto descriptivo: [Documentación de Markdown en Jira](https://support.atlassian.com/jira-software-cloud/docs/format-your-description-with-markdown/)

Imagen como enlace (si la URL es http/https): ![Logo de ejemplo](https://www.atlassian.com/dam/jcr:bc7c2a1e-0c4e-4f5e-8b5e-5e5e5e5e5e5e/atlassian-logo.png)

---

## Regla horizontal

Texto antes de la regla.

***

Más texto después. Las reglas pueden usar `---`, `***` o `___`.

___

---

## Párrafos largos y espaciado

Este es un párrafo extenso para probar el flujo de texto. Contiene varias oraciones que se extienden a lo largo de múltiples líneas. El objetivo es verificar que los saltos de línea y el espaciado entre párrafos se rendericen correctamente en la vista de descripción.

Un segundo párrafo separado por una línea en blanco. Aquí podemos incluir **palabras clave** y *términos técnicos* sin romper el flujo. También `variables` y [referencias](https://example.com) para asegurar que todo el formato inline funcione dentro de párrafos largos.

Un tercer párrafo más corto para contrastar.

---

## Jerarquía completa de encabezados (resumen)

# H1 — Nivel 1
## H2 — Nivel 2
### H3 — Nivel 3
#### H4 — Nivel 4
##### H5 — Nivel 5
###### H6 — Nivel 6

---

## Casos edge y combinaciones

- Lista con **negrita** en el primer elemento
- Lista con *cursiva* en el segundo
- Lista con `código` en el tercero
- Lista con [enlace](https://example.com) en el cuarto
- Lista con ***todo combinado*** en el quinto

1. Ordenada con **formato**
2. Ordenada con *énfasis*
3. Ordenada con `code`

> Cita que contiene una lista:
> - Item uno
> - Item dos
>
> Y un párrafo adicional con **negrita**.

---

## Fin del documento de prueba

Este documento cubre: **headings** (H1–H6), **negrita**, *cursiva*, `código`, [enlaces], listas con viñetas, listas numeradas, listas de tareas, blockquotes, bloques de código, reglas horizontales y párrafos con espaciado. Úsalo para validar que todos los elementos de la descripción se muestran correctamente en TaskDetailView.
