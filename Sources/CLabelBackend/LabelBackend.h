#ifndef LABEL_BACKEND_H
#define LABEL_BACKEND_H
#include <stdint.h>
#include <stddef.h>
// Returned UTF-8 JSON must be freed with label_backend_free.
char *label_backend_status(void);
// Pixels: row-major grayscale (0 black, 255 white), physical tape-sized bitmap.
// Memory is borrowed only for the duration of this synchronous call.
char *label_backend_print(const uint8_t *pixels, size_t count,
                         uint32_t width, uint32_t height,
                         uint8_t tape_mm, uint16_t copies, uint8_t cut);
void label_backend_free(char *message);
#endif
