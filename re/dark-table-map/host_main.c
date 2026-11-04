/* Research only: run decode.c on the Mac. Usage: host_main <light osos> <table> <output>.
 * The program copies the light osos into an area of 0x800000 bytes (the addresses that the decoder
 * can write), applies the table, and writes the first bytes (the size of the light osos).
 * The table is in a buffer of its exact size. Thus a build with -fsanitize=address finds each read
 * past the end of the table. test_ifd2.py and check.py compare the result with the Python build. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LIMIT 0x800000

void apply_table2(const unsigned *t);
unsigned char *host_base;

static unsigned char *load(const char *path, long *size)
{
    FILE *f = fopen(path, "rb");
    unsigned char *b;
    if (!f || fseek(f, 0, SEEK_END) != 0 || (*size = ftell(f)) < 0 || fseek(f, 0, SEEK_SET) != 0)
        exit(2);
    b = malloc(*size ? *size : 1);
    if (!b || fread(b, 1, *size, f) != (size_t)*size)
        exit(2);
    fclose(f);
    return b;
}

int main(int argc, char **argv)
{
    long n, tn;
    unsigned char *light, *table;
    FILE *f;
    if (argc != 4)
        return 1;
    light = load(argv[1], &n);
    table = load(argv[2], &tn);
    if (n > LIMIT || tn < 12)
        return 1;
    host_base = calloc(LIMIT, 1);
    if (!host_base)
        return 2;
    memcpy(host_base, light, n);
    apply_table2((const unsigned *)table);
    f = fopen(argv[3], "wb");
    if (!f || fwrite(host_base, 1, n, f) != (size_t)n || fclose(f) != 0)
        return 2;
    return 0;
}
