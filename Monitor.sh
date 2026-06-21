# Monitor.sh Sábado 20/06/2026


#!/bin/bash
# =================================================================
#  PROYECTO FASE 3 - SISTEMAS OPERATIVOS
#  Universidad Católica de Santa María
# -----------------------------------------------------------------
#  Archivo : monitor.sh
#  Autor   : Rojas Luna Kevin Jostin (2023803011)
#  Avance  : 65% - Script Bash principal
# -----------------------------------------------------------------
#  Integra:
#    - Expresiones Regulares (Guía 6)  -> validar_linea_log()
#    - Arreglos en Bash      (Guía 7)  -> historial_alertas[]
#    - Pipes / Tuberías      (Guía 8)  -> contar_procesos()
#    - Señales                (Guía 8)  -> trap SIGUSR1 / SIGTERM
#    - Lanza y controla monitor_hw.c en segundo plano
#
#  Ejecutar:
#    chmod +x monitor.sh
#    ./monitor.sh
#
#  Enviar señales desde otra terminal:
#    kill -SIGUSR1 <PID_mostrado_al_iniciar>   # volcar resumen
#    kill -SIGTERM <PID_mostrado_al_iniciar>   # cierre limpio
# =================================================================

# ╔═══════════════════════════════════════════════════════════════╗
# ║ NUEVO (65%): Variables y constantes globales                  ║
# ╚═══════════════════════════════════════════════════════════════╝
LOG_FILE="/dev/shm/syslog_ipc.txt"
BIN_HW="./monitor_hw"
PID_HW=""
MAX_HISTORIAL=10          # NUEVO (65%): tamaño máximo del arreglo de alertas

# ╔═══════════════════════════════════════════════════════════════╗
# ║ NUEVO (65%): ARREGLO BASH - historial de alertas (Guía 7)     ║
# ║ Arreglo indexado que guarda las últimas N alertas detectadas  ║
# ╚═══════════════════════════════════════════════════════════════╝
declare -a historial_alertas=()

# NUEVO (65%): Arreglo Bash con la lista de procesos a monitorear (Guía 7)
declare -a procesos_monitoreados=("monitor_hw" "bash" "gcc")

# ── Colores para terminal (mejora visual, no afecta la lógica) ──
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
AZUL='\033[0;34m'
NC='\033[0m'

# =================================================================
# NUEVO (65%): FUNCIÓN - Timestamp uniforme para todo el script
# =================================================================
obtener_timestamp() {
    date "+[%Y-%m-%d %H:%M:%S]"
}

# =================================================================
# NUEVO (65%): EXPRESIONES REGULARES (Guía 6)
# Valida que una línea del log cumpla el formato esperado:
#   [YYYY-MM-DD HH:MM:SS] [NIVEL] [FUENTE] mensaje
# Usa =~ (regex extendida de Bash) sobre cada línea.
# =================================================================
validar_linea_log() {
    local linea="$1"
    # Regex: fecha-hora entre [ ], luego nivel INFO|WARN|ERROR, luego fuente
    local patron='^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[(INFO|WARN|ERROR)\] \[[A-Z-]+\] .+$'

    if [[ "$linea" =~ $patron ]]; then
        return 0   # línea válida
    else
        return 1   # línea con formato incorrecto
    fi
}

# NUEVO (65%): Extrae el nivel de alerta (INFO/WARN/ERROR) de una línea usando regex
extraer_nivel() {
    local linea="$1"
    if [[ "$linea" =~ \[(INFO|WARN|ERROR)\] ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "DESCONOCIDO"
    fi
}

# =================================================================
# NUEVO (65%): GESTIÓN DEL ARREGLO DE HISTORIAL (Guía 7)
# Agrega una alerta al arreglo, manteniendo tamaño máximo
# (estructura tipo cola FIFO usando slicing de arreglo Bash)
# =================================================================
agregar_alerta() {
    local nivel="$1"
    local mensaje="$2"
    local entrada="$(obtener_timestamp) [$nivel] $mensaje"

    historial_alertas+=("$entrada")   # NUEVO (65%): inserción en el arreglo

    # Si el arreglo supera el máximo, eliminamos el elemento más antiguo
    if [ "${#historial_alertas[@]}" -gt "$MAX_HISTORIAL" ]; then
        historial_alertas=("${historial_alertas[@]:1}")   # slicing del arreglo
    fi
}

# NUEVO (65%): Muestra el contenido actual del arreglo de historial
mostrar_historial() {
    echo -e "${AZUL}── Historial de alertas (últimas ${#historial_alertas[@]}) ──${NC}"
    if [ "${#historial_alertas[@]}" -eq 0 ]; then
        echo "  (sin alertas registradas aún)"
    else
        local i=1
        for alerta in "${historial_alertas[@]}"; do
            echo "  $i) $alerta"
            ((i++))
        done
    fi
}

# =================================================================
# NUEVO (65%): PIPES / TUBERÍAS (Guía 8)
# Cuenta procesos activos encadenando comandos Linux:
#   ps aux | grep <proceso> | grep -v grep | wc -l
# =================================================================
contar_procesos() {
    local nombre_proceso="$1"
    local conteo

    # NUEVO (65%): pipe de 4 etapas: captura, filtra, excluye el propio grep, cuenta
    conteo=$(ps aux | grep "$nombre_proceso" | grep -v "grep" | wc -l)

    echo "$conteo"
}

# NUEVO (65%): Recorre el arreglo procesos_monitoreados[] usando pipes para cada uno
monitorear_procesos_activos() {
    echo -e "${AZUL}── Procesos monitoreados (pipes: ps | grep | wc -l) ──${NC}"
    for proceso in "${procesos_monitoreados[@]}"; do
        local cantidad
        cantidad=$(contar_procesos "$proceso")
        printf "  %-15s -> %s instancia(s) activa(s)\n" "$proceso" "$cantidad"
    done
}

# =================================================================
# NUEVO (65%): LECTURA Y VALIDACIÓN DEL LOG GENERADO POR monitor_hw.c
# Combina regex + arreglo: lee el log, valida cada línea y
# clasifica las alertas WARN/ERROR en el historial
# =================================================================
procesar_log() {
    [ -f "$LOG_FILE" ] || return

    while IFS= read -r linea; do
        if validar_linea_log "$linea"; then
            local nivel
            nivel=$(extraer_nivel "$linea")
            if [ "$nivel" = "WARN" ] || [ "$nivel" = "ERROR" ]; then
                agregar_alerta "$nivel" "$linea"   # NUEVO (65%): solo alertas relevantes van al arreglo
            fi
        fi
    done < "$LOG_FILE"
}

# =================================================================
# NUEVO (65%): SEÑALES ENTRE PROCESOS (Guía 8)
# trap captura señales enviadas con `kill -SIGNAL <PID>`
# =================================================================

# NUEVO (65%): Handler de SIGUSR1 -> vuelca resumen del log SIN detener el monitor
manejar_sigusr1() {
    echo ""
    echo -e "${AMARILLO}>>> SIGUSR1 recibida: volcando resumen del log <<<${NC}"
    procesar_log
    mostrar_historial
    monitorear_procesos_activos
    echo -e "${AMARILLO}>>> Fin del resumen. El monitoreo continúa... <<<${NC}"
    echo ""
}

# NUEVO (65%): Handler de SIGTERM -> cierre limpio liberando recursos
manejar_sigterm() {
    echo ""
    echo -e "${ROJO}>>> SIGTERM recibida: cerrando monitor limpiamente <<<${NC}"

    # Si el binario C sigue corriendo, se espera/termina ordenadamente
    if [ -n "$PID_HW" ] && kill -0 "$PID_HW" 2>/dev/null; then
        echo "Esperando a que monitor_hw finalice su ciclo actual..."
        wait "$PID_HW" 2>/dev/null
    fi

    echo "$(obtener_timestamp) [INFO] [MONITOR.SH] Cierre limpio por SIGTERM" >> "$LOG_FILE"
    echo -e "${ROJO}>>> Monitor finalizado correctamente. <<<${NC}"
    exit 0
}

# NUEVO (65%): Registro de los traps -> asocia señal con función manejadora
trap manejar_sigusr1 SIGUSR1
trap manejar_sigterm SIGTERM SIGINT

# =================================================================
# NUEVO (65%): LANZAMIENTO E INTEGRACIÓN CON monitor_hw.c
# Ejecuta el binario en C en segundo plano y guarda su PID
# =================================================================
lanzar_monitor_hw() {
    if [ ! -x "$BIN_HW" ]; then
        echo -e "${ROJO}ERROR: No se encontró el binario $BIN_HW${NC}"
        echo "Compílalo primero con: gcc -o monitor_hw monitor_hw.c -lpthread"
        exit 1
    fi

    "$BIN_HW" &           # NUEVO (65%): ejecución en background
    PID_HW=$!             # NUEVO (65%): captura del PID del proceso hijo

    echo -e "${VERDE}monitor_hw.c lanzado en segundo plano (PID=$PID_HW)${NC}"
}

# =================================================================
# PROGRAMA PRINCIPAL
# =================================================================
clear
echo "================================================================"
echo "   SYSLOG MONITOR - Sistemas Operativos Fase 3 (Avance 65%)"
echo "   Rojas Luna Kevin Jostin - 2023803011"
echo "================================================================"
echo ""
echo "PID de este script: $$"
echo "Para enviar señales desde otra terminal:"
echo "   kill -SIGUSR1 $$    -> volcar resumen sin detener"
echo "   kill -SIGTERM $$    -> cerrar limpiamente"
echo ""

# Inicializar log si no existe
[ -f "$LOG_FILE" ] || echo "$(obtener_timestamp) [INFO] [MONITOR.SH] Log inicializado" > "$LOG_FILE"

# NUEVO (65%): lanza el módulo C concurrente
lanzar_monitor_hw

echo ""
echo "Monitoreando... (Ctrl+C o SIGTERM para salir, SIGUSR1 para resumen)"
echo ""

# ── Bucle principal: espera señales o a que termine monitor_hw ──
# NUEVO (65%): mientras monitor_hw corre, el script queda receptivo a señales
while kill -0 "$PID_HW" 2>/dev/null; do
    sleep 1
done

# Si monitor_hw terminó solo (sin señal), procesamos el resultado final
echo ""
echo -e "${VERDE}monitor_hw finalizó su ciclo. Procesando resultados...${NC}"
procesar_log
mostrar_historial
monitorear_procesos_activos

echo ""
echo "================================================================"
echo "  Revisa el log completo en: $LOG_FILE"
echo "================================================================"
