#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static inline uint32_t rol32(uint32_t x, int n) {
    return (x << n) | (x >> (32 - n));
}

static void sha1_block(uint32_t st[5], const uint8_t block[64]) {
    uint32_t w[80];
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)block[i * 4] << 24) |
               ((uint32_t)block[i * 4 + 1] << 16) |
               ((uint32_t)block[i * 4 + 2] << 8) |
               ((uint32_t)block[i * 4 + 3]);
    }
    for (int i = 16; i < 80; i++) {
        w[i] = rol32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    uint32_t a = st[0], b = st[1], c = st[2], d = st[3], e = st[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20) { f = (b & c) | ((~b) & d); k = 0x5A827999; }
        else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
        else { f = b ^ c ^ d; k = 0xCA62C1D6; }
        uint32_t temp = rol32(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rol32(b, 30); b = a; a = temp;
    }
    st[0] += a; st[1] += b; st[2] += c; st[3] += d; st[4] += e;
}

/* Compute HOTP(key[10], counter=0) % mod */
static uint32_t hotp0_key10(const uint8_t key[10], uint32_t mod) {
    uint8_t blk[64];

    /* Inner hash: SHA1((key ^ 0x36) || 8 zero bytes) -> total 72 bytes (576 bits) */
    memset(blk, 0x36, 64);
    for (int i = 0; i < 10; i++) blk[i] ^= key[i];
    uint32_t ist[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0};
    sha1_block(ist, blk);

    memset(blk, 0, 64);
    blk[8] = 0x80;
    blk[62] = 0x02; /* 576 = 0x0240 */
    blk[63] = 0x40;
    sha1_block(ist, blk);

    /* Outer hash: SHA1((key ^ 0x5c) || inner_digest[20]) -> total 84 bytes (672 bits) */
    memset(blk, 0x5c, 64);
    for (int i = 0; i < 10; i++) blk[i] ^= key[i];
    uint32_t ost[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0};
    sha1_block(ost, blk);

    memset(blk, 0, 64);
    for (int i = 0; i < 5; i++) {
        blk[i * 4]     = (uint8_t)(ist[i] >> 24);
        blk[i * 4 + 1] = (uint8_t)(ist[i] >> 16);
        blk[i * 4 + 2] = (uint8_t)(ist[i] >> 8);
        blk[i * 4 + 3] = (uint8_t)(ist[i]);
    }
    blk[20] = 0x80;
    blk[62] = 0x02; /* 672 = 0x02A0 */
    blk[63] = 0xA0;
    sha1_block(ost, blk);

    uint8_t digest[20];
    for (int i = 0; i < 5; i++) {
        digest[i * 4]     = (uint8_t)(ost[i] >> 24);
        digest[i * 4 + 1] = (uint8_t)(ost[i] >> 16);
        digest[i * 4 + 2] = (uint8_t)(ost[i] >> 8);
        digest[i * 4 + 3] = (uint8_t)(ost[i]);
    }
    int off = digest[19] & 0x0F;
    uint32_t bin = (((uint32_t)digest[off] & 0x7F) << 24) |
                   ((uint32_t)digest[off + 1] << 16) |
                   ((uint32_t)digest[off + 2] << 8) |
                   ((uint32_t)digest[off + 3]);
    return bin % mod;
}

static const char B32[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

static void base32_encode_10(const uint8_t in[10], char out[17]) {
    uint64_t hi = ((uint64_t)in[0] << 32) | ((uint64_t)in[1] << 24) |
                  ((uint64_t)in[2] << 16) | ((uint64_t)in[3] << 8) | in[4];
    uint64_t lo = ((uint64_t)in[5] << 32) | ((uint64_t)in[6] << 24) |
                  ((uint64_t)in[7] << 16) | ((uint64_t)in[8] << 8) | in[9];
    for (int i = 0; i < 8; i++) out[i]     = B32[(hi >> (35 - 5 * i)) & 31];
    for (int i = 0; i < 8; i++) out[8 + i] = B32[(lo >> (35 - 5 * i)) & 31];
    out[16] = '\0';
}

typedef struct {
    uint32_t target;
    uint32_t mod;
    uint64_t seed_lo;
    uint16_t seed_hi;
    uint64_t tries;
    uint8_t found_key[10];
    int did_find;
} WorkerArg;

static atomic_int g_found = 0;

static void *worker_fn(void *arg) {
    WorkerArg *w = (WorkerArg *)arg;
    uint8_t key[10];
    key[0] = (uint8_t)(w->seed_hi >> 8);
    key[1] = (uint8_t)(w->seed_hi & 0xFF);
    uint64_t c = w->seed_lo;
    uint64_t tries = 0;

    while (!atomic_load_explicit(&g_found, memory_order_relaxed)) {
        for (int batch = 0; batch < 4096; batch++) {
            c++;
            tries++;
            key[2] = (uint8_t)(c >> 56);
            key[3] = (uint8_t)(c >> 48);
            key[4] = (uint8_t)(c >> 40);
            key[5] = (uint8_t)(c >> 32);
            key[6] = (uint8_t)(c >> 24);
            key[7] = (uint8_t)(c >> 16);
            key[8] = (uint8_t)(c >> 8);
            key[9] = (uint8_t)(c);
            if (hotp0_key10(key, w->mod) == w->target) {
                if (atomic_exchange(&g_found, 1) == 0) {
                    memcpy(w->found_key, key, 10);
                    w->did_find = 1;
                }
                w->tries = tries;
                return NULL;
            }
        }
    }
    w->tries = tries;
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <target_uint> <digits(4-9)>\n", argv[0]);
        return 2;
    }
    uint32_t target = (uint32_t)strtoul(argv[1], NULL, 10);
    int digits = atoi(argv[2]);
    if (digits < 4 || digits > 9) {
        fprintf(stderr, "digits must be 4..9\n");
        return 2;
    }
    uint32_t mod = 1;
    for (int i = 0; i < digits; i++) mod *= 10;
    if (target >= mod) {
        fprintf(stderr, "target out of range\n");
        return 2;
    }

    long ncpus = sysconf(_SC_NPROCESSORS_ONLN);
    if (ncpus < 1) ncpus = 4;
    if (ncpus > 32) ncpus = 32;

    FILE *ur = fopen("/dev/urandom", "rb");
    if (!ur) return 1;

    pthread_t threads[32];
    WorkerArg args[32];
    for (long i = 0; i < ncpus; i++) {
        args[i].target = target;
        args[i].mod = mod;
        args[i].tries = 0;
        args[i].did_find = 0;
        if (fread(&args[i].seed_lo, sizeof(uint64_t), 1, ur) != 1 ||
            fread(&args[i].seed_hi, sizeof(uint16_t), 1, ur) != 1) {
            fclose(ur);
            return 1;
        }
        pthread_create(&threads[i], NULL, worker_fn, &args[i]);
    }
    fclose(ur);

    uint64_t total_tries = 0;
    int winner = -1;
    for (long i = 0; i < ncpus; i++) {
        pthread_join(threads[i], NULL);
        total_tries += args[i].tries;
        if (args[i].did_find) winner = (int)i;
    }

    if (winner >= 0) {
        char sec[17];
        base32_encode_10(args[winner].found_key, sec);
        printf("%s %llu\n", sec, (unsigned long long)total_tries);
        return 0;
    }
    return 1;
}
