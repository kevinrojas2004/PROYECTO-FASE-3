#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>

/* ─── Constantes ─────────────────────────────────────────── */
#define LOG_FILE      "/dev/shm/syslog_ipc.txt"
#define INTERVALO_SEG  2      /* segundos entre cada lectura  */
#define ITERACIONES    5      /* cuántas veces mide cada hilo */
 
/* ─── Mutex global ───────────────────────────────────────── */
pthread_mutex_t mutex_log = PTHREAD_MUTEX_INITIALIZER;

/* ================================================================
 *  UTILIDAD: obtener timestamp formateado
 *  Formato: [YYYY-MM-DD HH:MM:SS]
 * ================================================================ */
void obtener_timestamp(char *buffer, size_t tam) {
    time_t ahora = time(NULL);
    struct tm *t = localtime(&ahora);
    strftime(buffer, tam, "[%Y-%m-%d %H:%M:%S]", t);
}
 
/* ================================================================
 *  UTILIDAD: escribir una línea en el log con mutex
 * ================================================================ */
void escribir_log(const char *nivel, const char *fuente, const char *mensaje) {
    char timestamp[32];
    obtener_timestamp(timestamp, sizeof(timestamp));
 
    /* SECCIÓN CRÍTICA: solo un hilo escribe a la vez */
    pthread_mutex_lock(&mutex_log);
 
    FILE *fp = fopen(LOG_FILE, "a");
    if (fp != NULL) {
        fprintf(fp, "%s [%s] [%s] %s\n", timestamp, nivel, fuente, mensaje);
        fflush(fp);
        fclose(fp);
    } else {
        /* Si no se puede abrir el log, imprimir en stderr */
        fprintf(stderr, "ERROR: No se pudo abrir el archivo de log: %s\n", LOG_FILE);
    }
 
    /* Mostrar en consola también */
    printf("%s [%s] [%s] %s\n", timestamp, nivel, fuente, mensaje);
 
    pthread_mutex_unlock(&mutex_log);
    /* FIN SECCIÓN CRÍTICA */
}
 
/* ================================================================
 *  HILO 1 - Monitoreo de CPU
 *  Lee el uso de CPU desde /proc/stat
 * ================================================================ */
void *hilo_cpu(void *arg) {
    char mensaje[256];
    unsigned long long user1, nice1, sys1, idle1, iowait1, irq1, sirq1;
    unsigned long long user2, nice2, sys2, idle2, iowait2, irq2, sirq2;
    double uso_cpu;
 
    escribir_log("INFO", "HILO-CPU", "Hilo de monitoreo CPU iniciado");
 
    for (int i = 0; i < ITERACIONES; i++) {
 
        /* Primera lectura de /proc/stat */
        FILE *fp1 = fopen("/proc/stat", "r");
        if (fp1 == NULL) {
            escribir_log("ERROR", "HILO-CPU", "No se pudo leer /proc/stat");
            pthread_exit(NULL);
        }
        fscanf(fp1, "cpu %llu %llu %llu %llu %llu %llu %llu",
               &user1, &nice1, &sys1, &idle1, &iowait1, &irq1, &sirq1);
        fclose(fp1);
 
        sleep(1); /* espera 1 segundo para calcular delta */
 
        /* Segunda lectura */
        FILE *fp2 = fopen("/proc/stat", "r");
        if (fp2 == NULL) {
            escribir_log("ERROR", "HILO-CPU", "No se pudo leer /proc/stat (segunda lectura)");
            pthread_exit(NULL);
        }
        fscanf(fp2, "cpu %llu %llu %llu %llu %llu %llu %llu",
               &user2, &nice2, &sys2, &idle2, &iowait2, &irq2, &sirq2);
        fclose(fp2);
 
        /* Cálculo del % de uso */
        unsigned long long total1 = user1 + nice1 + sys1 + idle1 + iowait1 + irq1 + sirq1;
        unsigned long long total2 = user2 + nice2 + sys2 + idle2 + iowait2 + irq2 + sirq2;
        unsigned long long delta_total = total2 - total1;
        unsigned long long delta_idle  = idle2  - idle1;
 
        if (delta_total == 0) {
            uso_cpu = 0.0;
        } else {
            uso_cpu = 100.0 * (1.0 - ((double)delta_idle / (double)delta_total));
        }
 
        /* Determinar nivel de alerta */
        const char *nivel;
        if (uso_cpu >= 80.0)      nivel = "WARN";
        else if (uso_cpu >= 95.0) nivel = "ERROR";
        else                       nivel = "INFO";
 
        snprintf(mensaje, sizeof(mensaje),
                 "Uso de CPU: %.2f%%  [iteracion %d/%d]",
                 uso_cpu, i + 1, ITERACIONES);
 
        escribir_log(nivel, "HILO-CPU", mensaje);
 
        sleep(INTERVALO_SEG);
    }
 
    escribir_log("INFO", "HILO-CPU", "Hilo CPU finalizado correctamente");
    pthread_exit(NULL);
}
 
/* ================================================================
 *  HILO 2 - Monitoreo de RAM
 *  Lee MemTotal, MemAvailable desde /proc/meminfo
 * ================================================================ */
void *hilo_ram(void *arg) {
    char mensaje[256];
    char linea[128];
    unsigned long long mem_total = 0, mem_disponible = 0;
    double uso_ram, porcentaje_libre;
 
    escribir_log("INFO", "HILO-RAM", "Hilo de monitoreo RAM iniciado");
 
    for (int i = 0; i < ITERACIONES; i++) {
 
        FILE *fp = fopen("/proc/meminfo", "r");
        if (fp == NULL) {
            escribir_log("ERROR", "HILO-RAM", "No se pudo leer /proc/meminfo");
            pthread_exit(NULL);
        }
 
        /* Leer línea a línea buscando MemTotal y MemAvailable */
        while (fgets(linea, sizeof(linea), fp)) {
            if (strncmp(linea, "MemTotal:", 9) == 0)
                sscanf(linea, "MemTotal: %llu kB", &mem_total);
            if (strncmp(linea, "MemAvailable:", 13) == 0)
                sscanf(linea, "MemAvailable: %llu kB", &mem_disponible);
        }
        fclose(fp);
 
        if (mem_total == 0) {
            escribir_log("ERROR", "HILO-RAM", "Datos de memoria no validos");
            sleep(INTERVALO_SEG);
            continue;
        }
 
        uso_ram        = (double)(mem_total - mem_disponible) / (double)mem_total * 100.0;
        porcentaje_libre = 100.0 - uso_ram;
 
        /* Nivel de alerta */
        const char *nivel;
        if (uso_ram >= 90.0)      nivel = "ERROR";
        else if (uso_ram >= 75.0) nivel = "WARN";
        else                       nivel = "INFO";
 
        snprintf(mensaje, sizeof(mensaje),
                 "RAM Total: %llu MB | Usada: %llu MB (%.2f%%) | Libre: %.2f%%",
                 mem_total / 1024,
                 (mem_total - mem_disponible) / 1024,
                 uso_ram,
                 porcentaje_libre);
 
        escribir_log(nivel, "HILO-RAM", mensaje);
 
        sleep(INTERVALO_SEG);
    }
 
    escribir_log("INFO", "HILO-RAM", "Hilo RAM finalizado correctamente");
    pthread_exit(NULL);
}
 
/* ================================================================
 *  HILO 3 - Monitoreo de Disco
 *  Usa statvfs() para obtener espacio en /
 * ================================================================ */
#include <sys/statvfs.h>
 
void *hilo_disco(void *arg) {
    char mensaje[256];
    struct statvfs stat;
    double total_gb, libre_gb, usado_gb, porcentaje_uso;
 
    escribir_log("INFO", "HILO-DISCO", "Hilo de monitoreo DISCO iniciado");
 
    for (int i = 0; i < ITERACIONES; i++) {
 
        if (statvfs("/", &stat) != 0) {
            escribir_log("ERROR", "HILO-DISCO", "No se pudo obtener info del disco con statvfs");
            sleep(INTERVALO_SEG);
            continue;
        }
 
        /* Calcular en GB */
        unsigned long long block_size = stat.f_frsize;
        total_gb = (double)(stat.f_blocks * block_size) / (1024.0 * 1024.0 * 1024.0);
        libre_gb = (double)(stat.f_bfree  * block_size) / (1024.0 * 1024.0 * 1024.0);
        usado_gb = total_gb - libre_gb;
        porcentaje_uso = (usado_gb / total_gb) * 100.0;
 
        /* Nivel de alerta */
        const char *nivel;
        if (porcentaje_uso >= 90.0)      nivel = "ERROR";
        else if (porcentaje_uso >= 75.0) nivel = "WARN";
        else                              nivel = "INFO";
 
        snprintf(mensaje, sizeof(mensaje),
                 "Disco /: Total=%.2f GB | Usado=%.2f GB (%.1f%%) | Libre=%.2f GB",
                 total_gb, usado_gb, porcentaje_uso, libre_gb);
 
        escribir_log(nivel, "HILO-DISCO", mensaje);
 
        sleep(INTERVALO_SEG);
    }
 
    escribir_log("INFO", "HILO-DISCO", "Hilo DISCO finalizado correctamente");
    pthread_exit(NULL);
}
 
/* ================================================================
 *  FUNCIÓN PRINCIPAL
 * ================================================================ */
int main(void) {
    pthread_t tid_cpu, tid_ram, tid_disco;
    char timestamp[32];
 
    printf("==============================================\n");
    printf("  MONITOR HW - Sistemas Operativos Fase 3\n");
    printf("  Rojas Luna Kevin Jostin - 2023803011\n");
    printf("==============================================\n\n");
 
    /* Inicializar el archivo de log */
    FILE *fp_init = fopen(LOG_FILE, "w");
    if (fp_init == NULL) {
        fprintf(stderr, "ERROR: No se puede crear el log en %s\n", LOG_FILE);
        fprintf(stderr, "Asegúrate de que /dev/shm/ exista (Ubuntu lo tiene por defecto)\n");
        return EXIT_FAILURE;
    }
    obtener_timestamp(timestamp, sizeof(timestamp));
    fprintf(fp_init, "%s [INFO] [SISTEMA] ===== INICIO DE MONITOREO CONCURRENTE =====\n", timestamp);
    fclose(fp_init);
 
    printf("Log creado en: %s\n\n", LOG_FILE);
    printf("Iniciando 3 hilos concurrentes...\n\n");
 
    /* ── Crear los 3 hilos ───────────────────────────────── */
    if (pthread_create(&tid_cpu, NULL, hilo_cpu, NULL) != 0) {
        perror("Error creando hilo CPU");
        return EXIT_FAILURE;
    }
 
    if (pthread_create(&tid_ram, NULL, hilo_ram, NULL) != 0) {
        perror("Error creando hilo RAM");
        return EXIT_FAILURE;
    }
 
    if (pthread_create(&tid_disco, NULL, hilo_disco, NULL) != 0) {
        perror("Error creando hilo DISCO");
        return EXIT_FAILURE;
    }
 
    /* ── Esperar a que todos los hilos terminen ──────────── */
    pthread_join(tid_cpu,   NULL);
    pthread_join(tid_ram,   NULL);
    pthread_join(tid_disco, NULL);
 
    /* ── Escribir fin de monitoreo ───────────────────────── */
    escribir_log("INFO", "SISTEMA", "===== FIN DE MONITOREO CONCURRENTE =====");
 
    /* Destruir el mutex */
    pthread_mutex_destroy(&mutex_log);
 
    printf("\n==============================================\n");
    printf("  Monitoreo completado.\n");
    printf("  Revisa el log en: %s\n", LOG_FILE);
    printf("  Comando: cat %s\n", LOG_FILE);
    printf("==============================================\n");
 
    return EXIT_SUCCESS;
}
