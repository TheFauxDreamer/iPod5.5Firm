/* Research only: run decode.c on the Mac. Usage: host_main <light osos> <table> <output>.
 * The program applies the table to the light osos and writes the result. check.py compares it with
 * the dark image of the Python build. */
#include <stdio.h>
#include <stdlib.h>

void apply_table2(const unsigned *t);
unsigned char *host_base;

static unsigned char *load(const char *path, long *size)
{
    FILE *f = fopen(path, "rb");
    unsigned char *b;
    if (!f || fseek(f, 0, SEEK_END) != 0 || (*size = ftell(f)) < 0 || fseek(f, 0, SEEK_SET) != 0)
        exit(2);
    b = malloc(*size + 4);
    if (!b || fread(b, 1, *size, f) != (size_t)*size)
        exit(2);
    fclose(f);
    return b;
}

int main(int argc, char **argv)
{
    long n, tn;
    FILE *f;
    if (argc != 4)
        return 1;
    host_base = load(argv[1], &n);
    apply_table2((const unsigned *)load(argv[2], &tn));
    f = fopen(argv[3], "wb");
    if (!f || fwrite(host_base, 1, n, f) != (size_t)n || fclose(f) != 0)
        return 2;
    return 0;
}
