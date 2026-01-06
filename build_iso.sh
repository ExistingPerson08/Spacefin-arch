#!/bin/bash
# Skript pro sestavení ISO obrazu pomocí bootc-image-builder

# ------------------------------------------------------------------------------
# 1. Definice Konstant a Vstupů (ENV)
# ------------------------------------------------------------------------------

# Statické Proměnné
GITHUB_REPOSITORY_OWNER="váš_github_uživatel" # ZMĚŇTE NA SVŮJ NÁZEV REPOZITÁŘE
DEFAULT_TAG="latest"
BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"

# Vstupní Proměnné S3 (Pro nahrávání)
# Tyto by měly být buď předem nastaveny v prostředí nebo vloženy sem.
S3_PROVIDER="${S3_PROVIDER:-unset}"
S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-unset}"
S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-unset}"
S3_REGION="${S3_REGION:-unset}"
S3_ENDPOINT="${S3_ENDPOINT:-unset}"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-unset}"

# Typ disku je pevně nastaven, aby se zjednodušila matice
DISK_TYPE="anaconda-iso"
DISK_TYPE_HYPHENED="anaconda-iso"

# UID/GID pro správné nastavení práv k výstupnímu souboru
USER_UID=$(id -u)
USER_GID=$(id -g)

# ------------------------------------------------------------------------------
# 2. Interaktivní Vstupy
# ------------------------------------------------------------------------------

echo "--- Interaktivní Vstupy pro Sestavení ISO ---"

# Vstup pro Platformu
while true; do
    read -r -p "Zadejte Platformu (amd64 / arm64): " PLATFORM
    if [[ "$PLATFORM" =~ ^(amd64|arm64)$ ]]; then
        break
    else
        echo "Neplatný výběr. Zadejte 'amd64' nebo 'arm64'."
    fi
done

# Vstup pro Edici
while true; do
    read -r -p "Zadejte Edici (cosmic / gnome / niri / kde): " EDITION
    if [[ "$EDITION" =~ ^(cosmic|gnome|niri|kde)$ ]]; then
        break
    else
        echo "Neplatný výběr. Zadejte jednu z možností: cosmic, gnome, niri, kde."
    fi
done

# Vstup pro Upload
while true; do
    read -r -p "Nahrát na S3 po sestavení (true / false): " UPLOAD_TO_S3
    if [[ "$UPLOAD_TO_S3" =~ ^(true|false)$ ]]; then
        break
    else
        echo "Neplatný výběr. Zadejte 'true' nebo 'false'."
    fi
done

echo "--- Kontrola Konfigurace ---"

# ------------------------------------------------------------------------------
# 3. Zpracování Proměnných
# ------------------------------------------------------------------------------

IMAGE_NAME="spacefin-${EDITION}"
IMAGE_REGISTRY="ghcr.io/${GITHUB_REPOSITORY_OWNER}"

# Převod na malá písmena
IMAGE_REGISTRY_LOWERCASE=${IMAGE_REGISTRY,,}
IMAGE_NAME_LOWERCASE=${IMAGE_NAME,,}

CONFIG_FILE="./disk_config/${EDITION}.toml"
BUILD_IMAGE="${IMAGE_REGISTRY_LOWERCASE}/${IMAGE_NAME_LOWERCASE}:${DEFAULT_TAG}"
OUTPUT_DIRECTORY="output-$DISK_TYPE_HYPHENED"

echo "Platforma: $PLATFORM"
echo "Edice: $EDITION"
echo "Sestavovaný obraz: $BUILD_IMAGE"
echo "Konfigurační soubor: $CONFIG_FILE"
echo "Výstupní složka: $OUTPUT_DIRECTORY"
echo "Nahrát na S3: $UPLOAD_TO_S3"
echo "-----------------------------"

# ------------------------------------------------------------------------------
# 4. Sestavení Disk Image (anaconda-iso)
# ------------------------------------------------------------------------------

echo "Spouštění sestavení ISO obrazu pro $EDITION ($PLATFORM)..."

# Odebrání starého výstupu
rm -rf "$OUTPUT_DIRECTORY"
mkdir -p "$OUTPUT_DIRECTORY"

# Spuštění bootc-image-builder v kontejneru
# POZNÁMKA: Použijeme stabilnější veřejný obraz z Quay.io.
sudo podman run --privileged \
    -v "$(pwd):/input:z" \
    -v "$(pwd)/$OUTPUT_DIRECTORY:/output:z" \
    --rm \
    "$BIB_IMAGE" \
    --output-directory "/output" \
    --chown "$USER_UID:$USER_GID" \
    --use-librepo=True

BUILD_EXIT_CODE=$?
if [ $BUILD_EXIT_CODE -ne 0 ]; then
    echo "CHYBA: Sestavení ISO selhalo s kódem $BUILD_EXIT_CODE."
    exit 1
fi

echo "Sestavení ISO dokončeno. Soubory jsou v adresáři: $OUTPUT_DIRECTORY"

# ------------------------------------------------------------------------------
# 5. Volitelné nahrání na S3
# ------------------------------------------------------------------------------

if [ "$UPLOAD_TO_S3" = "true" ]; then
    echo "Spouštění nahrávání na S3..."

    # Nastavení prostředí pro rclone (musíte mít nainstalovaný rclone)
    export RCLONE_CONFIG_S3_TYPE="s3"
    export RCLONE_CONFIG_S3_PROVIDER="${S3_PROVIDER}"
    export RCLONE_CONFIG_S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}"
    export RCLONE_CONFIG_S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}"
    export RCLONE_CONFIG_S3_REGION="${S3_REGION}"
    export RCLONE_CONFIG_S3_ENDPOINT="${S3_ENDPOINT}"

    if [ -d "$OUTPUT_DIRECTORY" ]; then
        # Kontrola kritických S3 proměnných
        if [ "$S3_BUCKET_NAME" = "unset" ] || [ "$S3_ACCESS_KEY_ID" = "unset" ]; then
            echo "CHYBA S3: Nemáte nastavené všechny potřebné proměnné pro S3 (např. S3_BUCKET_NAME nebo S3_ACCESS_KEY_ID)."
            echo "Nahrávání přeskočeno."
        else
            rclone copy "$OUTPUT_DIRECTORY" "S3:$S3_BUCKET_NAME"
            echo "Nahrání na S3 dokončeno."
        fi
    else
        echo "Varování: Výstupní adresář $OUTPUT_DIRECTORY nebyl nalezen pro nahrání na S3."
    fi

    # Vyčištění proměnných prostředí rclone
    unset RCLONE_CONFIG_S3_TYPE RCLONE_CONFIG_S3_PROVIDER RCLONE_CONFIG_S3_ACCESS_KEY_ID RCLONE_CONFIG_S3_SECRET_ACCESS_KEY RCLONE_CONFIG_S3_REGION RCLONE_CONFIG_S3_ENDPOINT

fi

echo "--- Skript dokončen ---"
