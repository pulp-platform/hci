# HCI SystemVerilog Coding Style Guide
HCI and related IPs use their own coding style that is similar, but not identical, to that of many other PULP IPs.
Most of the changes are due to preference by the benevelent dictator and main author of these IPs, i.e., yours truly, `FrancescoConti88`: I add a comment on the reason of the change near to it.
Many of these are subjective, you are free to disagree - but hey, this is my town and I make the rules.
You can follow the lowRISC guidelines https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md with several changes or extra recommendations, some of which are pretty major:

1. `begin` is on its own line in `always`, `always_comb`, and `always_ff` blocks
```
always_ff @(posedge clk)
begin
  // content
end
```
*I find this to be better readable than the lowRISC standard.*

2. Always start a new line before `else`:
```
if (condition) begin
  foo = bar;
end
else begin
  foo = bum;
end
```
*It is much easier to see an `else` than one of the many `end`s in code, so I prefer this to the lowRISC style.*

3. Avoid non-unavoidable preprocessor directives and macros.
*Basically you will see only `ifdef SYNTHESIS` and `ifdef VERILATOR`. These can almost always be replaced by parameters and other constructs.*

4. Parameters and constants are `ALL_CAPS`.
*Just a style choice, but better to be consistent in new modules in the HCI family.*

5. Avoid parametric types and do not overuse of `typedef`s.
*I hate parametric types. They may make the code easier to write, but they make it very difficult to read and interpret, and we spend only 10% of our coding time writing code, the rest is reading! The same can be said of other `typedef`s (for example in a package) to a (much) lower degree. Their main advantage is compile-time type checking, which is nice, but the cost is code readability... For simple logic vectors I prefer to use plain `logic`s.*

6. All flip-flops must have an asynchronous negative edge-triggered reset (typically `rst_ni`), a "soft" synchronous clear (`clear_i`).
*The system asynchronous reset and the soft clear serve wholly different purposes. Both should be used in all flip-flops in HCI IPs.*

7. All flip-flops should have an enable signal indicated __inside the `always_ff` block__:
```
always_ff @(posedge clk_i or negedge rst_ni)
begin
  if(~rst_ni)
    q <= '0;
  else if(clear_i)
    q <= '0;
  else if(enable_signal_or_condition)
    q <= d;
end
```
*Although it is recommended to keep combinational logic outside of `always_ff`'s, enable conditions should be there explicitly, otherwise some tools do not correctly infer clock gating cells!*

8. Combinational logic can be expressed with continuous assignments (`assign a = b | c`) or `always_comb` blocks. In the latter case, always include a default value for all outputs.
*Self-explanatory common sense rule!*

9. No `x` values permitted.
*Don't care conditions should be avoided to avoid RTL/gate-level mismatches.*

10. Avoid too complex `always_comb` blocks.
*Complex combinational logic should be split as much as possible in elementary, explainable units. It should be immediately clear to what a certain line corresponds in RTL terms (a multiplexer, a battery of AND gates, etc.). Often it is easier to achieve this goal by using `assign` blocks, but in some cases this is impossible, or impacts readability.*

11. `interface`s can (and must) be used.
*The kind of parametric behavior we wrap in HCI IPs can only be coded in SystemVerilog using `interface`s or coupling `struct`s with auxiliary non-SystemVerilog code generators. The latter solution works very well for fixed-size buses and can be adapted to the case where there is at least a maximum size, but it  is IMHO a doorway to over-engineering as it requires external tools, it generates multiple copies of very similar code into an unmaintainable "SystemVerilog blob". It is a reasonable solution when nothing else exists, but `interface`s exist and they are actually pretty awesome. In the following a few guidelines to use `interface`s productively and without losing control.*

12. Use `interface`s to implement buses, without internal logic; limit `modport`s to the two directions plus possibly an extra "monitoring" one.
*Internal logic makes interfaces difficult to use and understand, and it is unnecessary - we have `module`s.*

13. Do not indicate `modport`s when connecting an interface hierarchically, e.g.:
```
hci_core_fifo i_fifo (
    .clk_i          ( clk_i   ),
    .rst_ni         ( rst_ni  ),
    .clear_i        ( clear_i ),
    .flags_o        ( flags   ),
    .tcdm_target    ( push    ), // interface target modport
    .tcdm_initiator ( pop     )  // interface initiator modport
);
```
*Some tools do not support indicating `modport`s explicitly, other tools simply ignore them. It is anyways an unnecessary complication to indicate them!*

14. Arrays of `interfaces` must be indicated in Verilog-style (`a[0:N-1]`), not C-style (`a[N]`), with indeces going upwards:
```
  hci_core_intf hci [0:NB_CHAN-1] (
    .clk ( clk_i )
  );
```
*It is particularly important that all interfaces in the system follow the same convention; the Verilog one is the best supported common ground.*

15. Use assertions inside `interface`s, waive them only if you are reasonably sure that they must be waived!
*One of the useful properties of `interface`s compared to plain `struct`s is that they can carry assertions without cluttering the code.*

16. As a corollary of 3, the usage of flip-flop macros (e.g., from https://github.com/pulp-platform/common_cells/blob/master/include/common_cells/registers.svh), common in many PULP IPs, is __discouraged__ in HWPE-style accelerators using HCI IPs.
*I believe the only benefit of these is to save time in writing code. But they do that at the expense of readability and understandability, which are severely hindered. They also introduce potential subtle bugs. It is my strong opinion that we should focus instead on making code readable & debuggable, as we spend >90% of our design time in reading and debugging code. Making code faster to write is a design anti-pattern.*
