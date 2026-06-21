# Avances del Proyecto
/*
 * =============================================================
 *  PROYECTO FASE 3 - SISTEMAS OPERATIVOS
 *  Universidad Católica de Santa María
 *  Escuela Profesional de Ingeniería de Sistemas
 * -------------------------------------------------------------
 *  Archivo   : monitor_hw.c
 *  Autor     : Rojas Luna Kevin Jostin (2023803011)
 *  Fecha     : 14/06/2026
 *  Avance    : 25% - Módulo C con hilos POSIX y mutex
 * -------------------------------------------------------------
 *  Descripción:
 *    Programa en C que crea 3 hilos concurrentes para monitorear
 *    CPU, RAM y Disco en paralelo. Cada hilo escribe sus métricas
 *    en un archivo de log compartido (/dev/shm/syslog_ipc.txt),
 *    sincronizado mediante un mutex para evitar condiciones de carrera.
 *
 *  Compilar:
 *    gcc -o monitor_hw monitor_hw.c -lpthread
 *
 *  Ejecutar:
 *    ./monitor_hw
 * =============================================================
 */

20/06/2026

/*
 * =============================================================
 *  PROYECTO FASE 3 - SISTEMAS OPERATIVOS
 *  Universidad Católica de Santa María
 *  Escuela Profesional de Ingeniería de Sistemas
 * -------------------------------------------------------------
 *  Archivo   : monitor_hw.c
 *  Autor     : Rojas Luna Kevin Jostin (2023803011)
 *  Fecha     : 20/06/2026
 *  Avance    : 65% - Módulo C con hilos POSIX, mutex y señales
 * -------------------------------------------------------------
 *  Descripción:
 *    Programa en C que crea 3 hilos concurrentes para monitorear
 *    CPU, RAM y Disco en paralelo. Cada hilo escribe sus métricas
 *    en un archivo de log compartido (/dev/shm/syslog_ipc.txt),
 *    sincronizado mediante un mutex para evitar condiciones de carrera.
 *
 *  NUEVO (65%): Ahora responde a señales SIGTERM/SIGINT enviadas
 *  desde monitor.sh (o manualmente), permitiendo un cierre limpio
 *  de los hilos sin esperar a que terminen sus 5 iteraciones.
 *
 *  Compilar:
 *    gcc -o monitor_hw monitor_hw.c -lpthread
 *
 *  Ejecutar:
 *    ./monitor_hw
 * =============================================================
 */
