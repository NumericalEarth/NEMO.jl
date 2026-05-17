#define _XOPEN_SOURCE 600
#include <setjmp.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>

#define ERROR_MESSAGE_CAPACITY 512

static char error_message[ERROR_MESSAGE_CAPACITY];
static int  error_message_length = 0;
static sigjmp_buf error_jump_buffer;
static int  error_jump_armed = 0;

extern void nemo_internal_init(int mpi_communicator);
extern void nemo_internal_step(void);
extern void nemo_internal_finalize(void);

static void store_error_message(const char *string, size_t length)
{
    if (length >= ERROR_MESSAGE_CAPACITY) length = ERROR_MESSAGE_CAPACITY - 1;
    memcpy(error_message, string, length);
    error_message[length]  = '\0';
    error_message_length   = (int) length;
}

void _gfortran_stop_string(const char *string, size_t length, bool quiet)
{
    (void) quiet;
    if (string != NULL && length > 0) {
        store_error_message(string, length);
    } else {
        store_error_message("Fortran STOP", 12);
    }
    if (error_jump_armed) {
        error_jump_armed = 0;
        siglongjmp(error_jump_buffer, 1);
    }
    fprintf(stderr, "NEMO STOP outside safe wrapper: %.*s\n",
            (int) length, string ? string : "");
    fflush(stderr);
    _exit(1);
}

void _gfortran_error_stop_string(const char *string, size_t length, bool quiet)
{
    _gfortran_stop_string(string, length, quiet);
}

void _gfortran_stop_numeric(int code, bool quiet)
{
    (void) quiet;
    char buffer[64];
    int length = snprintf(buffer, sizeof(buffer), "Fortran STOP code %d", code);
    if (length > 0) store_error_message(buffer, (size_t) length);
    if (error_jump_armed) {
        error_jump_armed = 0;
        siglongjmp(error_jump_buffer, 1);
    }
    fprintf(stderr, "%s outside safe wrapper\n", buffer);
    fflush(stderr);
    _exit(1);
}

void _gfortran_exit_i4(int code)
{
    char buffer[64];
    int length = snprintf(buffer, sizeof(buffer), "Fortran EXIT code %d", code);
    if (length > 0) store_error_message(buffer, (size_t) length);
    if (error_jump_armed) {
        error_jump_armed = 0;
        siglongjmp(error_jump_buffer, 1);
    }
    fprintf(stderr, "%s outside safe wrapper\n", buffer);
    fflush(stderr);
    _exit(code != 0 ? code : 1);
}

void _gfortran_exit_i8(long code)
{
    _gfortran_exit_i4((int) code);
}

void _gfortran_abort(void)
{
    store_error_message("Fortran ABORT", 13);
    if (error_jump_armed) {
        error_jump_armed = 0;
        siglongjmp(error_jump_buffer, 1);
    }
    fprintf(stderr, "Fortran ABORT outside safe wrapper\n");
    fflush(stderr);
    _exit(1);
}

void nemo_clear_error_message(void)
{
    error_message[0]     = '\0';
    error_message_length = 0;
}

void nemo_get_error_message(char *buffer, int *buffer_length)
{
    int capacity = *buffer_length;
    int copied   = (error_message_length < capacity) ? error_message_length : capacity;
    if (copied > 0) memcpy(buffer, error_message, (size_t) copied);
    *buffer_length = copied;
}

int nemo_initialize(int mpi_communicator)
{
    nemo_clear_error_message();
    if (sigsetjmp(error_jump_buffer, 1) != 0) {
        return 1;
    }
    error_jump_armed = 1;
    nemo_internal_init(mpi_communicator);
    error_jump_armed = 0;
    return 0;
}

int nemo_step(void)
{
    nemo_clear_error_message();
    if (sigsetjmp(error_jump_buffer, 1) != 0) {
        return 1;
    }
    error_jump_armed = 1;
    nemo_internal_step();
    error_jump_armed = 0;
    return 0;
}

int nemo_finalize(void)
{
    nemo_clear_error_message();
    if (sigsetjmp(error_jump_buffer, 1) != 0) {
        return 1;
    }
    error_jump_armed = 1;
    nemo_internal_finalize();
    error_jump_armed = 0;
    return 0;
}
