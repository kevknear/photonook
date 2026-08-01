# Fuentes

Aquí van los archivos de **Caveat**, la tipografía manuscrita de marca.

## Qué descargar

1. Entra en <https://fonts.google.com/specimen/Caveat>
2. Pulsa **Get font** → **Download all**
3. Descomprime el `.zip`
4. Abre la carpeta **`static/`** (no uses el archivo variable `Caveat-VariableFont_wght.ttf`,
   los nombres PostScript de las variables dan problemas con `Font.custom`)
5. Copia estos dos archivos a esta misma carpeta:

```
Caveat-Regular.ttf
Caveat-Bold.ttf
```

Los nombres deben coincidir exactamente: están declarados en `Sources/Info.plist`
bajo `UIAppFonts` y referenciados en el proyecto.

## Licencia

Caveat se distribuye bajo la **SIL Open Font License 1.1**, que permite empaquetarla
en aplicaciones comerciales sin coste ni atribución dentro de la app. Conserva el
archivo `OFL.txt` del zip junto a las fuentes.

## Si el texto sale con la fuente del sistema

Significa que iOS no encontró la fuente. Comprueba, por este orden:

1. Que los dos `.ttf` están físicamente en esta carpeta.
2. Que aparecen marcados en *Target Membership* dentro de Xcode.
3. Que el nombre PostScript es el esperado. Para verlo, añade temporalmente esto
   al `init()` de `PhotoNookApp`:

   ```swift
   for family in UIFont.familyNames where family.contains("Caveat") {
       print(family, UIFont.fontNames(forFamilyName: family))
   }
   ```

   Debe imprimir `Caveat ["Caveat-Regular", "Caveat-Bold"]`. Si imprime otros
   nombres, ajústalos en `Font.handwritten` dentro de `Theme.swift`.
