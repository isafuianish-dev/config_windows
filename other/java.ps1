# Installs Eclipse Temurin OpenJDK 21 via winget. JAVA_HOME and PATH are set by
# ps_profile\module\env.ps1 once it's installed.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, not UTF-8.

winget install -e --accept-package-agreements --accept-source-agreements --silent --id EclipseAdoptium.Temurin.21.JDK
