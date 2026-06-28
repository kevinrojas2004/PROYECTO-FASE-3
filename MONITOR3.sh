#!/bin/bash
# =================================================================
#  PROYECTO FASE 3 - SISTEMAS OPERATIVOS
#  Universidad Católica de Santa María
# -----------------------------------------------------------------
#  Archivo : monitor.sh
#  Autor   : Rojas Luna Kevin Jostin (2023803011)
#  Avance  : 100% - Script Bash principal (versión final)
# -----------------------------------------------------------------
#  Integra:
#    - Expresiones Regulares (Guía 6)  -> validar_linea_log()
#    - Arreglos en Bash      (Guía 7)  -> historial_alertas[]
#    - Pipes / Tuberías      (Guía 8)  -> contar_procesos()
#    - Señales                (Guía 8)  -> trap SIGUSR1/SIGUSR2/SIGTERM
#    - Lanza y controla monitor_hw.c en segundo plano
#    - NUEVO (100%): Dashboard de estadísticas (promedios, picos, totales)
#    - NUEVO (100%): Rotación automática de logs por número de líneas
#
#  Ejecutar:
#    chmod +x monitor.sh
#    ./monitor.sh
#
#  Enviar señales desde otra terminal:
#    kill -SIGUSR1 <PID>   # volcar resumen (historial + procesos)
#    kill -SIGUSR2 <PID>   # NUEVO (100%): volcar dashboard de estadísticas
#    kill -SIGTERM <PID>   # cierre limpio + dashboard final
# =================================================================

# ╔═══════════════════════════════════════════════════════════════╗
# ║ NUEVO (65%): Variables y constantes globales                  ║
# ╚═══════════════════════════════════════════════════════════════╝
LOG_FILE="/dev/shm/syslog_ipc.txt"
BIN_HW="./monitor_hw"
PID_HW=""
PID_FILE="./monitor.pid"            # NUEVO (100%): permite que monitor_control.sh
                                     # encuentre el PID sin que el usuario lo copie a mano
ESTADO_FILE="./monitor_estado.txt"  # NUEVO (100%): estado legible para consulta externa
BUZON_FILE="./monitor_buzon.txt"    # NUEVO (100%): buzón de mensajes entre terminales
PAUSADO=0                           # NUEVO (100%): bandera de pausa del monitoreo
MAX_HISTORIAL=10          # NUEVO (65%): tamaño máximo del arreglo de alertas
MAX_LINEAS_LOG=200        # NUEVO (100%): umbral de rotación del log (en líneas)
DIR_ROTADOS="./logs_rotados"  # NUEVO (100%): carpeta donde se archivan logs viejos

# ╔═══════════════════════════════════════════════════════════════╗
# ║ NUEVO (65%): ARREGLO BASH - historial de alertas (Guía 7)     ║
# ║ Arreglo indexado que guarda las últimas N alertas detectadas  ║
# ╚═══════════════════════════════════════════════════════════════╝
declare -a historial_alertas=()

# NUEVO (65%): Arreglo Bash con la lista de procesos a monitorear (Guía 7)
declare -a procesos_monitoreados=("monitor_hw" "bash" "gcc")

# ╔═══════════════════════════════════════════════════════════════╗
# ║ NUEVO (100%): Arreglos para el dashboard de estadísticas      ║
# ║ Guardan cada lectura numérica de CPU y RAM para calcular      ║
# ║ promedio y pico máximo al final del monitoreo                 ║
# ╚═══════════════════════════════════════════════════════════════╝
declare -a lecturas_cpu=()
declare -a lecturas_ram=()
declare -i contador_info=0    # NUEVO (100%): totales por nivel de alerta
declare -i contador_warn=0
declare -i contador_error=0

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
# clasifica las alertas relevantes en el historial
#
# NUEVO (100%): además extrae los valores numéricos de CPU y RAM
# con regex para alimentar el dashboard de estadísticas, y cuenta
# cuántas líneas hay de cada nivel (INFO/WARN/ERROR)
# =================================================================
procesar_log() {
    [ -f "$LOG_FILE" ] || return

    # NUEVO (100%): reiniciar contadores/arreglos antes de re-procesar
    lecturas_cpu=()
    lecturas_ram=()
    contador_info=0
    contador_warn=0
    contador_error=0

    while IFS= read -r linea; do
        if validar_linea_log "$linea"; then
            local nivel
            nivel=$(extraer_nivel "$linea")

            # NUEVO (100%): conteo total por nivel para el dashboard
            case "$nivel" in
                INFO)  ((contador_info++))  ;;
                WARN)  ((contador_warn++))  ;;
                ERROR) ((contador_error++)) ;;
            esac

            if [ "$nivel" = "WARN" ] || [ "$nivel" = "ERROR" ]; then
                agregar_alerta "$nivel" "$linea"   # NUEVO (65%): solo alertas relevantes van al arreglo
            fi

            # NUEVO (100%): extraer el % de CPU con regex si la línea es de HILO-CPU
            if [[ "$linea" =~ HILO-CPU.*Uso\ de\ CPU:\ ([0-9]+\.[0-9]+)% ]]; then
                lecturas_cpu+=("${BASH_REMATCH[1]}")
            fi

            # NUEVO (100%): extraer el % de RAM con regex si la línea es de HILO-RAM
            if [[ "$linea" =~ HILO-RAM.*\(([0-9]+\.[0-9]+)%\) ]]; then
                lecturas_ram+=("${BASH_REMATCH[1]}")
            fi
        fi
    done < "$LOG_FILE"
}

# =================================================================
# NUEVO (100%): DASHBOARD DE ESTADÍSTICAS
# Calcula promedio y pico máximo de CPU/RAM a partir de los
# arreglos llenados en procesar_log(), y muestra los totales
# de alertas por nivel. Usa awk para las operaciones con
# decimales, ya que la aritmética nativa de Bash es solo entera.
# =================================================================
calcular_promedio() {
    local -n arreglo_ref=$1     # NUEVO (100%): referencia al arreglo (nameref)
    if [ "${#arreglo_ref[@]}" -eq 0 ]; then
        echo "0.00"
        return
    fi
    printf "%s\n" "${arreglo_ref[@]}" | awk '{ suma+=$1; n++ } END { printf "%.2f", suma/n }'
}

calcular_pico() {
    local -n arreglo_ref=$1
    if [ "${#arreglo_ref[@]}" -eq 0 ]; then
        echo "0.00"
        return
    fi
    printf "%s\n" "${arreglo_ref[@]}" | sort -n | tail -1
}

mostrar_dashboard() {
    local prom_cpu pico_cpu prom_ram pico_ram total_lineas

    prom_cpu=$(calcular_promedio lecturas_cpu)
    pico_cpu=$(calcular_pico lecturas_cpu)
    prom_ram=$(calcular_promedio lecturas_ram)
    pico_ram=$(calcular_pico lecturas_ram)
    total_lineas=$((contador_info + contador_warn + contador_error))

    echo -e "${AZUL}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${AZUL}║       DASHBOARD DE ESTADÍSTICAS (100%)        ║${NC}"
    echo -e "${AZUL}╚══════════════════════════════════════════════╝${NC}"
    printf "  CPU   -> Promedio: %6s%%   Pico: %6s%%\n" "$prom_cpu" "$pico_cpu"
    printf "  RAM   -> Promedio: %6s%%   Pico: %6s%%\n" "$prom_ram" "$pico_ram"
    echo "  ------------------------------------------------"
    printf "  Total de líneas procesadas : %d\n" "$total_lineas"
    echo -e "  ${VERDE}INFO  : $contador_info${NC}"
    echo -e "  ${AMARILLO}WARN  : $contador_warn${NC}"
    echo -e "  ${ROJO}ERROR : $contador_error${NC}"
    echo -e "${AZUL}══════════════════════════════════════════════════${NC}"
}

# =================================================================
# NUEVO (100%): ROTACIÓN AUTOMÁTICA DE LOGS (por número de líneas)
# Si el log supera MAX_LINEAS_LOG, se archiva con timestamp en
# DIR_ROTADOS y se crea un log nuevo y vacío, dejando una línea
# de continuidad que referencia el archivo anterior.
# =================================================================
rotar_log_si_excede() {
    [ -f "$LOG_FILE" ] || return

    local total_lineas
    total_lineas=$(wc -l < "$LOG_FILE")

    if [ "$total_lineas" -gt "$MAX_LINEAS_LOG" ]; then
        mkdir -p "$DIR_ROTADOS"   # NUEVO (100%): crea la carpeta si no existe

        local nombre_archivo="syslog_$(date +%Y%m%d_%H%M%S).txt"
        mv "$LOG_FILE" "$DIR_ROTADOS/$nombre_archivo"

        echo -e "${AMARILLO}>>> Log rotado: superó $MAX_LINEAS_LOG líneas ($total_lineas) <<<${NC}"
        echo -e "${AMARILLO}>>> Archivo anterior guardado en: $DIR_ROTADOS/$nombre_archivo <<<${NC}"

        # Nuevo log vacío con referencia al archivo rotado
        echo "$(obtener_timestamp) [INFO] [MONITOR.SH] Log rotado. Anterior: $nombre_archivo" > "$LOG_FILE"
    fi
}

# =================================================================
# NUEVO (100%): ARCHIVO DE ESTADO PARA CONSULTA EXTERNA
# Escribe en disco el estado actual (corriendo/pausado, PIDs,
# última actualización) para que monitor_control.sh pueda leerlo
# sin necesidad de enviar ninguna señal (consulta no invasiva).
# =================================================================
actualizar_estado() {
    local estado_txt="EN EJECUCION"
    [ "$PAUSADO" -eq 1 ] && estado_txt="PAUSADO"
    {
        echo "ESTADO=$estado_txt"
        echo "PID_SCRIPT=$$"
        echo "PID_HW=$PID_HW"
        echo "ULTIMA_ACTUALIZACION=$(obtener_timestamp)"
    } > "$ESTADO_FILE"
}

# =================================================================
# NUEVO (100%): BUZÓN DE MENSAJES ENTRE TERMINALES
# El script principal revisa este archivo cada segundo dentro de
# su bucle de espera. Si monitor_control.sh escribió algo nuevo,
# se muestra en la Terminal 1 y luego se vacía el buzón.
# =================================================================
revisar_buzon() {
    [ -s "$BUZON_FILE" ] || return    # -s: el archivo existe y no está vacío
    echo ""
    echo -e "${AZUL}┌─ MENSAJE RECIBIDO DESDE OTRA TERMINAL ──────┐${NC}"
    while IFS= read -r msg; do
        echo "  > $msg"
    done < "$BUZON_FILE"
    echo -e "${AZUL}└──────────────────────────────────────────────┘${NC}"
    echo ""
    : > "$BUZON_FILE"                 # vacía el buzón tras leerlo
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

# NUEVO (100%): Handler de SIGUSR2 -> vuelca el dashboard de estadísticas a demanda
manejar_sigusr2() {
    echo ""
    echo -e "${AMARILLO}>>> SIGUSR2 recibida: calculando dashboard de estadísticas <<<${NC}"
    procesar_log
    mostrar_dashboard
    echo -e "${AMARILLO}>>> Fin del dashboard. El monitoreo continúa... <<<${NC}"
    echo ""
}

# ───────────────────────────────────────────────────────────────
# NUEVO (100%): PAUSAR / REANUDAR EL ESCANEO
# Se usa SIGSTOP/SIGCONT (señales nativas del kernel) en vez de
# una bandera propia: el kernel congela TODO el proceso monitor_hw
# de forma atómica, incluidos sus 3 hilos, sin riesgo de que un
# hilo quede sosteniendo el mutex a medias. Al reanudar, cada hilo
# continúa exactamente donde se quedó. No requiere cambios en
# monitor_hw.c porque SIGSTOP no puede ser interceptada ni
# bloqueada por ningún proceso (es manejada directamente por el
# sistema operativo).
# ───────────────────────────────────────────────────────────────
manejar_sigtstp() {
    if [ "$PAUSADO" -eq 1 ]; then
        echo -e "${AMARILLO}El monitoreo ya está en pausa.${NC}"
        return
    fi
    if [ -z "$PID_HW" ] || ! kill -0 "$PID_HW" 2>/dev/null; then
        echo -e "${ROJO}No hay un proceso monitor_hw activo para pausar.${NC}"
        return
    fi

    kill -SIGSTOP "$PID_HW"      # NUEVO (100%): congela los 3 hilos al instante
    PAUSADO=1
    actualizar_estado
    echo ""
    echo -e "${AMARILLO}>>> Monitoreo PAUSADO (SIGSTOP enviado a monitor_hw, PID=$PID_HW) <<<${NC}"
    echo -e "${AMARILLO}>>> Usa monitor_control.sh reanudar para continuar <<<${NC}"
    echo ""
}

manejar_sigcont() {
    if [ "$PAUSADO" -eq 0 ]; then
        return    # evita mensajes duplicados si no estaba pausado
    fi
    if [ -z "$PID_HW" ] || ! kill -0 "$PID_HW" 2>/dev/null; then
        return
    fi

    kill -SIGCONT "$PID_HW"      # NUEVO (100%): reanuda exactamente donde se quedó
    PAUSADO=0
    actualizar_estado
    echo ""
    echo -e "${VERDE}>>> Monitoreo REANUDADO (SIGCONT enviado a monitor_hw) <<<${NC}"
    echo ""
}

# NUEVO (65%/100%): Handler de SIGTERM -> cierre limpio liberando recursos
# NUEVO (100%): ahora reenvía la señal al binario C para activar su cierre
# anticipado (terminar_programa=1) en vez de esperar pasivamente a que
# termine sus 5 iteraciones por su cuenta. También muestra el dashboard
# final y limpia los archivos de control (pid/estado).
manejar_sigterm() {
    echo ""
    echo -e "${ROJO}>>> SIGTERM recibida: cerrando monitor limpiamente <<<${NC}"

    if [ -n "$PID_HW" ] && kill -0 "$PID_HW" 2>/dev/null; then
        # NUEVO (100%): si estaba pausado, hay que reanudarlo primero,
        # de lo contrario kill -SIGTERM quedaría pendiente sin entregarse
        if [ "$PAUSADO" -eq 1 ]; then
            kill -SIGCONT "$PID_HW" 2>/dev/null
        fi

        # NUEVO (100%): reenvía SIGTERM al proceso C -> activa terminar_programa
        kill -SIGTERM "$PID_HW" 2>/dev/null
        echo "Señal reenviada a monitor_hw (PID=$PID_HW). Esperando cierre de hilos..."
        wait "$PID_HW" 2>/dev/null
    fi

    echo "$(obtener_timestamp) [INFO] [MONITOR.SH] Cierre limpio por SIGTERM" >> "$LOG_FILE"

    procesar_log
    mostrar_historial
    mostrar_dashboard          # NUEVO (100%): dashboard final automático al cerrar

    rm -f "$PID_FILE" "$ESTADO_FILE"   # NUEVO (100%): limpieza de archivos de control

    echo -e "${ROJO}>>> Monitor finalizado correctamente. <<<${NC}"
    exit 0
}

# NUEVO (100%): Registro de los traps -> ahora incluye SIGUSR2, SIGTSTP y SIGCONT
trap manejar_sigusr1 SIGUSR1
trap manejar_sigusr2 SIGUSR2
trap manejar_sigtstp SIGTSTP
trap manejar_sigcont SIGCONT
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
echo "   SYSLOG MONITOR - Sistemas Operativos Fase 3 (Avance 100%)"
echo "   Rojas Luna Kevin Jostin - 2023803011"
echo "================================================================"
echo ""
echo "PID de este script: $$"
echo "$$" > "$PID_FILE"     # NUEVO (100%): guarda el PID en disco para que
                            # monitor_control.sh lo lea automáticamente
echo ""
echo "Opción recomendada (desde otra terminal, en esta misma carpeta):"
echo "   ./monitor_control.sh resumen          -> ver historial sin detener"
echo "   ./monitor_control.sh stats            -> ver dashboard de estadísticas"
echo "   ./monitor_control.sh pausar            -> pausar el escaneo"
echo "   ./monitor_control.sh reanudar          -> reanudar el escaneo"
echo "   ./monitor_control.sh mensaje \"texto\"   -> enviar un mensaje"
echo "   ./monitor_control.sh detener           -> cerrar todo limpiamente"
echo "   ./monitor_control.sh estado            -> ver estado actual"
echo ""
echo "Alternativa manual (si prefieres usar kill directamente):"
echo "   kill -SIGUSR1 $$    -> resumen          kill -SIGUSR2 $$  -> stats"
echo "   kill -SIGTSTP $$    -> pausar           kill -SIGCONT $$  -> reanudar"
echo "   kill -SIGTERM $$    -> cerrar"
echo ""

# Inicializar log si no existe
[ -f "$LOG_FILE" ] || echo "$(obtener_timestamp) [INFO] [MONITOR.SH] Log inicializado" > "$LOG_FILE"

# NUEVO (100%): vacía el buzón de mensajes al iniciar una nueva sesión
: > "$BUZON_FILE"

# NUEVO (65%): lanza el módulo C concurrente
lanzar_monitor_hw
actualizar_estado          # NUEVO (100%): primer registro de estado

echo ""
echo "Monitoreando... (ver arriba los comandos disponibles)"
echo ""

# ── Bucle principal: espera señales o a que termine monitor_hw ──
# NUEVO (100%): cada segundo, además de comprobar si monitor_hw sigue
# vivo, se refresca el estado, se revisa el buzón de mensajes y se
# comprueba si el log necesita rotación.
while kill -0 "$PID_HW" 2>/dev/null; do
    sleep 1
    actualizar_estado
    revisar_buzon
    rotar_log_si_excede
done

# Si monitor_hw terminó solo (sin señal), procesamos el resultado final
echo ""
echo -e "${VERDE}monitor_hw finalizó su ciclo. Procesando resultados...${NC}"
procesar_log
mostrar_historial
monitorear_procesos_activos
mostrar_dashboard            # NUEVO (100%): dashboard también en el cierre natural

rm -f "$PID_FILE" "$ESTADO_FILE"   # NUEVO (100%): limpieza al terminar sin señal

echo ""
echo "================================================================"
echo "  Revisa el log completo en: $LOG_FILE"
echo "================================================================"
