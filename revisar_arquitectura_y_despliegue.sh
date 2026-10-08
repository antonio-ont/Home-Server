#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE REVISIÓN Y DESPLIEGUE TÉCNICO - PROYECTO HOME SERVER & DISPLAY IoT
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}   HOME SERVER & SMART FRAME - ARQUITECTURA TÉCNICA & AUDITORÍA IA${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
}

export_ai_prompt() {
    echo -e "${GREEN}[+] Generando archivo de auditoría PROMPT_REVISION_IA.md para pasar a otras IAs...${NC}"
    cat << 'EOF' > PROMPT_REVISION_IA.md
# Prompt de Auditoría y Revisión de Arquitectura para Ingenieros y Modelos LLM

Actúa como un Ingeniero Principal de Infraestructura (Principal DevOps / Embedded Systems Architect).
Por favor, revisa y evalúa la viabilidad técnica de la siguiente arquitectura:

## 1. Contexto y Objetivos del Proyecto
- **Host Central:** Portátil antiguo x86_64 reconvertido a Home Server 24/7 (Soberanía de datos, fotos y streaming familiar).
- **Cliente Display:** Samsung Galaxy Tab 4 (1.5 GB RAM, hardware legacy) como marco digital interactivo.
- **Seguridad Batería:** Sistema automatizado de control de carga (20%-80%) para mitigar riesgos térmicos en celda Li-ion.
- **Portafolio:** Diseñado para demostrar competencias en SysAdmin Linux, Docker, Redes, Reverse Proxy y Desarrollo a medida.

## 2. Stack Tecnológico Seleccionado
- **OS Servidor:** Ubuntu Server 24.04 LTS (Headless, suspensión deshabilitada en /etc/systemd/logind.conf).
- **Contenedores:** Docker + Docker Compose con redes puente aisladas.
- **Fotos (Nube Privada):** Immich (PostgreSQL 16 con pgvector, Redis, Microservicios de indexación).
- **Streaming (Multimedia):** Jellyfin (Direct Play en LAN, clientes en Smart TV y móvil).
- **Proxy & TLS:** Caddy Server con configuración simplificada y certificados locales.
- **Red Remota:** Tailscale (WireGuard mesh network, sin necesidad de abrir puertos NAT).
- **Frontend Tablet:** SPA ligera en Vanilla JS / Svelte montada en modo quiosco consumiendo API REST de Immich.
- **Control Batería:** Daemon Python con polling de batería por ADB Wi-Fi + control REST de enchufe inteligente.

## 3. Preguntas Clave para tu Análisis de Ingeniería
1. **Cuellos de Botella y Rendimiento:** ¿Qué limitaciones de I/O de disco y memoria RAM se presentarán al indexar bibliotecas de más de 50.000 fotos en un portátil antiguo con HDD mecánico? ¿Cómo mitigarlo?
2. **Resiliencia de la Tablet:** ¿Cuál es la estrategia óptima para evitar fugas de memoria en el navegador web de la Galaxy Tab 4 funcionando 30+ días seguidos?
3. **Seguridad y Backups:** ¿Qué esquema de respaldos (ej. 3-2-1 con Restic/BorgBackup) recomendarías implementar para asegurar que las fotos nunca se pierdan en caso de fallo físico del disco?
4. **Impacto en CV:** ¿Cómo resumirías este proyecto en un CV técnico para postular a roles Junior/Mid de DevOps, SysAdmin o Full-Stack?

Identifica riesgos ocultos, posibles puntos únicos de fallo (SPOF) y mejoras recomendadas.
EOF
    echo -e "${GREEN}[✓] PROMPT_REVISION_IA.md generado.${NC}"
}

generate_all_templates() {
    export_ai_prompt

    echo -e "${GREEN}[+] Generando docker-compose.yml de referencia...${NC}"
    cat << 'EOF' > docker-compose.yml
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy_proxy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - internal_net

  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich_server
    restart: always
    environment:
      - DB_HOSTNAME=immich_postgres
      - DB_USERNAME=immich
      - DB_PASSWORD=immich_password_segura
      - DB_DATABASE_NAME=immich
      - REDIS_HOSTNAME=immich_redis
    volumes:
      - /mnt/storage/fotos:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    depends_on:
      - immich_redis
      - immich_postgres
    networks:
      - internal_net

  immich_redis:
    image: redis:7-alpine
    container_name: immich_redis
    restart: always
    networks:
      - internal_net

  immich_postgres:
    image: tensorchord/pgvecto-rs:pg16-v0.2.0
    container_name: immich_postgres
    restart: always
    environment:
      - POSTGRES_PASSWORD=immich_password_segura
      - POSTGRES_USER=immich
      - POSTGRES_DB=immich
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - internal_net

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin_media
    restart: always
    volumes:
      - ./jellyfin_config:/config
      - ./jellyfin_cache:/cache
      - /mnt/storage/media/movies:/data/movies:ro
      - /mnt/storage/media/shows:/data/shows:ro
    networks:
      - internal_net

volumes:
  caddy_data:
  caddy_config:
  pgdata:

networks:
  internal_net:
    driver: bridge
EOF

    echo -e "${GREEN}[+] Generando daemon de control de batería (battery_guardian.py)...${NC}"
    cat << 'EOF' > battery_guardian.py
#!/usr/bin/env python3
import subprocess
import time
import requests
import sys

TABLET_IP = "192.168.1.50:5555"
SMART_PLUG_API = "http://192.168.1.100/api/relay"
MIN_THRESHOLD = 25
MAX_THRESHOLD = 80
POLL_INTERVAL = 300

def get_battery_level():
    try:
        subprocess.run(["adb", "connect", TABLET_IP], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        out = subprocess.check_output(["adb", "-s", TABLET_IP, "shell", "dumpsys", "battery"], timeout=5).decode('utf-8')
        for line in out.splitlines():
            if "level:" in line:
                return int(line.split(":")[1].strip())
    except Exception as e:
        print(f"[!] Error leyendo telemetria: {e}", file=sys.stderr)
    return None

def set_plug_state(turn_on: bool):
    state = "on" if turn_on else "off"
    try:
        requests.post(f"{SMART_PLUG_API}?state={state}", timeout=5)
        print(f"[*] Enchufe conmutado a: {state.upper()}")
    except Exception as e:
        print(f"[!] Error conmutando enchufe: {e}", file=sys.stderr)

def main():
    print(f"[*] Monitorizando bateria en {TABLET_IP}")
    while True:
        level = get_battery_level()
        if level is not None:
            print(f"[*] Bateria actual: {level}%")
            if level <= MIN_THRESHOLD:
                set_plug_state(True)
            elif level >= MAX_THRESHOLD:
                set_plug_state(False)
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
EOF

    echo -e "\n${GREEN}[✓] Todos los archivos generados correctamente.${NC}"
}

if [ "${1:-}" = "--all" ]; then
    generate_all_templates
else
    print_header
    echo "1) Generar todo (Docker Compose, Python Daemon y Prompt para IAs)"
    echo "2) Generar unicamente PROMPT_REVISION_IA.md"
    echo "3) Salir"
    echo ""
    read -rp "Selecciona una opción [1-3]: " opt
    case "$opt" in
        1) generate_all_templates ;;
        2) export_ai_prompt; cat PROMPT_REVISION_IA.md ;;
        3) exit 0 ;;
        *) echo -e "${RED}Opción no válida.${NC}" ;;
    esac
fi
