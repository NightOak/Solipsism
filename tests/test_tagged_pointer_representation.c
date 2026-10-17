#include <assert.h>
#include <stdint.h>
#include <stdio.h>

/* This is a representation-only test, not an embedded SpiderMonkey test. */
static int private_value_representable(uint64_t p) {
    return (p & UINT64_C(0x00ff000000000000)) == 0 &&
           p <= UINT64_C(0xfff80000ffffffff);
}
static uint64_t private_slot_bits(uint64_t p) {
    assert(private_value_representable(p));
    return p;  /* PrivateValue uses AsJSVal(ptrBits), with no masking. */
}
int main(void) {
    const uint64_t tagged = UINT64_C(0xb400006abbad0050);
    const uint64_t plain  = UINT64_C(0x0000006abbad0050);
    assert(private_slot_bits(tagged) == tagged);
    assert(private_slot_bits(plain) == plain);
    assert(private_slot_bits(0) == 0);
    assert(!private_value_representable(UINT64_C(0xb420006abbad0050)));
    assert(!private_value_representable(UINT64_C(0xfff8000000000000)));
    puts("PASS: Android TBI tag preserved; invalid high payload and JS-tagged range rejected");
    return 0;
}
