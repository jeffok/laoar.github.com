---
layout: post
title: "loop unrolling : may or may not make the program run faster"
date: 2014-11-26 21:58:59 +0800
comments: true
categories: 
---

<p>loop unrolling 是将while/for循环的循环主体多排列几次展开以减少循环次数，从而减少分支指令开销来达到优化性能的目的。我们可以手动的修改while/for循环来展开循环体，也可以使用编译器的自动循环展开功能。gcc的-funroll-loops就是用来自动将循环给展开用的。在gcc的手册里，对于-funroll-loops有一句说明，“This option makes code larger, and may or may not make it run faster.”，其实这句话并不是很准确，确切的说法是，“This option may improves or reduces the performance.”。</p>
<p>在最近我的做的一个项目中，版本做出大幅度升级后，性能下降了30%多，经过各种排查后发现原来是编译器从Gcc-4.1.1升级为Gcc-4.2.1后-funroll-loops的行为发生了变化，使得在循环展开的过程中产生了大量的temp variables，这些temp variables入栈和出栈占用了大量的cpu cycles，从而使得其中一个线程成为bottleneck，性能因此下降了30%多.</p>
<p>在这篇博客里，来分析下loop unrolling为什么会导致性能下降</p>
<p>如下是我写的一个测试程序用来描述该问题。</p>

``` c
#define TIMES 2
static inline void
atomic_write64 (u_int64_t *addr, u_int64_t val)
{
    volatile u_int32_t val_hi = val >> 32;
    volatile u_int32_t val_lo = val;

  asm  volatile("    .set push           \n"
                "    .set mips64         \n"
                "    dsll   %1, %1, 32   \n"
                "    dsll   %2, %2, 32   \n"
                "    dsrl   %2, %2, 32   \n"
                "    or     %1, %1, %2   \n"
                "    dsll   %0, %0, 32   \n"
                "    dsrl   %0, %0, 32   \n"
                "    sd     %1, 0(%0)    \n"
                "    .set pop            \n"
                :
                :"r"(addr), "r" (val_hi), "r" (val_lo)
               );
}


int main()
{
    int i;
    u_int64_t x;
    u_int64_t *addr = (u_int64_t *)malloc(sizeof(u_int64_t) * 2);
    u_int64_t *new_addr = (u_int64_t *)((unsigned int)addr & 0xfffffff8);

    for (i = 0; i < TIMES; i++) {
        // The value of random() is 32bits.
        x = (u_int64_t)random() << 32 + random();
        atomic_write64(new_addr, x);
    }

    return 0;
}
```
<p>对该测试程序的一些注释：<br/>
<1> 该atomic function摘自freebsd source code。<br/>
<2> 使用的编译器是Gcc-4.2.1，平台是MIPS（该CPU是64bit的CPU），ABI是O32.[1]<br>
<3> 之所以要new_addr的低3bits要为0，是由于sd指令要求地址必须是8字节对齐。  这里就是O32和N32区别的一个体现，O32的寄存器是32bits，所以它的栈空间是4字节对齐，即指针是4字节对齐的；N32的寄存器是64bits，所以它的栈空间是64bits，即指针是8字节对齐。在N32上就不需要做这种处理。<br/>
<4> 由于CPU的寄存器是64bits，所以dsll将寄存器左移32bits后会将寄存器内容移到高32bits，实际上这里是变相在使用N32的特性，即64bit寄存器.<br/>
<5> 为了便于理解反汇编，gcc的优化option使用-O.<br/>
<6> 之所以初始测试条件是TIMES为2，而不是1，是为了防止for循环被编译器给优化掉。</p>

<p>我们编译该程序，然后看反汇编结果：</p>

```c
00000000 <main>:
   0:   3c1c0000    lui gp,0x0
   4:   279c0000    addiu   gp,gp,0
   8:   0399e021    addu    gp,gp,t9
   c:   27bdffc8    addiu   sp,sp,-56
  10:   afbf0034    sw  ra,52(sp)
  14:   afb40030    sw  s4,48(sp)
  18:   afb3002c    sw  s3,44(sp)
  1c:   afb20028    sw  s2,40(sp)
  20:   afb10024    sw  s1,36(sp)
  24:   afb00020    sw  s0,32(sp)
  28:   afbc0010    sw  gp,16(sp)
  2c:   8f990000    lw  t9,0(gp)
  30:   0320f809    jalr    t9
  34:   24040010    li  a0,16
  38:   8fbc0010    lw  gp,16(sp)
  3c:   2403fff8    li  v1,-8
  40:   0043a024    and s4,v0,v1
  44:   00009021    move    s2,zero
  48:   8f990000    lw  t9,0(gp)
  4c:   03209821    move    s3,t9
  50:   0260c821    move    t9,s3
  54:   0320f809    jalr    t9
  58:   00008821    move    s1,zero
  5c:   8fbc0010    lw  gp,16(sp)
  60:   0260c821    move    t9,s3
  64:   0320f809    jalr    t9
  68:   00408021    move    s0,v0
  6c:   8fbc0010    lw  gp,16(sp)
  70:   00401821    move    v1,v0
  74:   000217c3    sra v0,v0,0x1f
  78:   02028025    or  s0,s0,v0
  7c:   02238825    or  s1,s1,v1
  80:   afb00018    sw  s0,24(sp)
  84:   afb1001c    sw  s1,28(sp)
  88:   8fa30018    lw  v1,24(sp)
  8c:   8fa2001c    lw  v0,28(sp)
  90:   0003183c    dsll32  v1,v1,0x0
  94:   0002103c    dsll32  v0,v0,0x0
  98:   0002103e    dsrl32  v0,v0,0x0
  9c:   00621825    or  v1,v1,v0
  a0:   0014a03c    dsll32  s4,s4,0x0
  a4:   0014a03e    dsrl32  s4,s4,0x0
  a8:   fe830000    sd  v1,0(s4)
  ac:   26520001    addiu   s2,s2,1
  b0:   24020002    li  v0,2
  b4:   1642ffe7    bne s2,v0,54 <main+0x54>
  b8:   0260c821    move    t9,s3
  bc:   00001021    move    v0,zero
  c0:   8fbf0034    lw  ra,52(sp)
  c4:   8fb40030    lw  s4,48(sp)
  c8:   8fb3002c    lw  s3,44(sp)
  cc:   8fb20028    lw  s2,40(sp)
  d0:   8fb10024    lw  s1,36(sp)
  d4:   8fb00020    lw  s0,32(sp)
  d8:   03e00008    jr  ra
  dc:   27bd0038    addiu   sp,sp,56
```
<p>可以看出，变量val_hi和val_lo分别存储在24(sp)和28(sp)这部分内存空间.</p>
<p>另外还需要注意的变量x。<br/>
```c
  64:   0320f809    jalr    t9
  68:   00408021    move    s0,v0
  6c:   8fbc0010    lw  gp,16(sp)
  70:   00401821    move    v1,v0
```
由于我只是-C来编译，并没有做链接，所以在这里调用random()这个函数是被编译为了”jalr t9”，在MIPS上，函数调用的返回值会放在$v0这个寄存器里面。[2]在这里函数调用的返回值$v0 是直接赋值给了$s0和$v1，而不是放入栈空间，这说明编译器将变量x存储在了寄存器里面而不是内存里面。编译器之所以会这么做，是为了提高性能。变量尽可能的存储在寄存器上，从而减少访问内存所需要消耗的时间。另外再说一句，寄存器数量是有限的，当寄存器无法再存储变量时，就会将临时变量存储到内存上。</p>
</p>然后我们将TIME 变为3，对比看下有无funroll-loops下的差异。</p>
1) 无funroll-loops.
<p>结果证明，跟TIMES为2的情况下相比，反汇编结果一样。此处不再拷贝代码</p>
2） 使用funroll-loops
<p> 汇编代码较长，闪花了眼，我在后面只解释重点。</p>
```c
00000000 <main>:
   0:   3c1c0000    lui gp,0x0
   4:   279c0000    addiu   gp,gp,0
   8:   0399e021    addu    gp,gp,t9
   c:   27bdff58    addiu   sp,sp,-168
  10:   afbf00a4    sw  ra,164(sp)
  14:   afbe00a0    sw  s8,160(sp)
  18:   afb7009c    sw  s7,156(sp)
  1c:   afb60098    sw  s6,152(sp)
  20:   afb50094    sw  s5,148(sp)
  24:   afb40090    sw  s4,144(sp)
  28:   afb3008c    sw  s3,140(sp)
  2c:   afb20088    sw  s2,136(sp)
  30:   afb10084    sw  s1,132(sp)
  34:   afb00080    sw  s0,128(sp)
  38:   afbc0010    sw  gp,16(sp)
  3c:   00003821    move    a3,zero
  40:   00003021    move    a2,zero
  44:   afa70024    sw  a3,36(sp)
  48:   afa60020    sw  a2,32(sp)
  4c:   afa7002c    sw  a3,44(sp)
  50:   afa60028    sw  a2,40(sp)
  54:   afa7003c    sw  a3,60(sp)
  58:   afa60038    sw  a2,56(sp)
  5c:   00002021    move    a0,zero
  60:   00001821    move    v1,zero
  64:   afa40044    sw  a0,68(sp)
  68:   afa30040    sw  v1,64(sp)
  6c:   afa4004c    sw  a0,76(sp)
  70:   afa30048    sw  v1,72(sp)
  74:   afa40054    sw  a0,84(sp)
  78:   afa30050    sw  v1,80(sp)
  7c:   afa4005c    sw  a0,92(sp)
  80:   afa30058    sw  v1,88(sp)
  84:   afa40064    sw  a0,100(sp)
  88:   afa30060    sw  v1,96(sp)
 8c:   afa4006c    sw  a0,108(sp)
  90:   afa30068    sw  v1,104(sp)
  94:   afa40074    sw  a0,116(sp)
  98:   afa30070    sw  v1,112(sp)
  9c:   afa4007c    sw  a0,124(sp)
  a0:   afa30078    sw  v1,120(sp)
  a4:   8f990000    lw  t9,0(gp)
  a8:   0320f809    jalr    t9
  ac:   24040010    li  a0,16
  b0:   8fbc0010    lw  gp,16(sp)
  b4:   2405fff8    li  a1,-8
  b8:   00451024    and v0,v0,a1
  bc:   8f990000    lw  t9,0(gp)
  c0:   0320f809    jalr    t9
  c4:   afa20030    sw  v0,48(sp)
  c8:   8fbc0010    lw  gp,16(sp)
  cc:   8f990000    lw  t9,0(gp)
  d0:   0320f809    jalr    t9
  d4:   00408021    move    s0,v0
  d8:   8fbc0010    lw  gp,16(sp)
  dc:   0000a821    move    s5,zero
  e0:   0002c7c3    sra t8,v0,0x1f
  e4:   0218b825    or  s7,s0,t8
  e8:   afb70028    sw  s7,40(sp)
  ec:   02a2a025    or  s4,s5,v0
  f0:   afb4002c    sw  s4,44(sp)
  f4:   8fb1002c    lw  s1,44(sp)
  f8:   8fb30028    lw  s3,40(sp)
  fc:   afb30018    sw  s3,24(sp)
100:   afb1001c    sw  s1,28(sp)
104:   8fae0018    lw  t6,24(sp)
108:   8faf001c    lw  t7,28(sp)
10c:   8fa50030    lw  a1,48(sp)
110:   000e703c    dsll32  t6,t6,0x0
114:   000f783c    dsll32  t7,t7,0x0
118:   000f783e    dsrl32  t7,t7,0x0
11c:   01cf7025    or  t6,t6,t7
120:   0005283c    dsll32  a1,a1,0x0
124:   0005283e    dsrl32  a1,a1,0x0
128:   fcae0000    sd  t6,0(a1)
12c:   8f990000    lw  t9,0(gp)
130:   0320f809    jalr    t9
134:   0000f021    move    s8,zero
138:   8fbc0010    lw  gp,16(sp)
13c:   8f990000    lw  t9,0(gp)
140:   0320f809    jalr    t9
144:   00408021    move    s0,v0
148:   8fbc0010    lw  gp,16(sp)
14c:   afb00044    sw  s0,68(sp)
150:   001067c3    sra t4,s0,0x1f
154:   afac0040    sw  t4,64(sp)
158:   8fab0044    lw  t3,68(sp)
15c:   afab0048    sw  t3,72(sp)
160:   00005021    move    t2,zero
164:   afaa004c    sw  t2,76(sp)
168:   8fa60048    lw  a2,72(sp)
16c:   afa20054    sw  v0,84(sp)
170:   000247c3    sra t0,v0,0x1f
174:   afa80050    sw  t0,80(sp)
178:   8fa30054    lw  v1,84(sp)
17c:   8fa70050    lw  a3,80(sp)
180:   00c72025    or  a0,a2,a3
184:   afa40020    sw  a0,32(sp)
188:   8fa5004c    lw  a1,76(sp)
18c:   00a31025    or  v0,a1,v1
190:   afa20024    sw  v0,36(sp)
194:   8fbf0020    lw  ra,32(sp)
198:   afbf005c    sw  ra,92(sp)
19c:   afbe0058    sw  s8,88(sp)
1a0:   8fb8005c    lw  t8,92(sp)
1a4:   afb80018    sw  t8,24(sp)
1a8:   8fb70024    lw  s7,36(sp)
 1ac:   afb7001c    sw  s7,28(sp)
1b0:   8fb50018    lw  s5,24(sp)
1b4:   8fb6001c    lw  s6,28(sp)
1b8:   8fa40030    lw  a0,48(sp)
1bc:   0015a83c    dsll32  s5,s5,0x0
1c0:   0016b03c    dsll32  s6,s6,0x0
1c4:   0016b03e    dsrl32  s6,s6,0x0
1c8:   02b6a825    or  s5,s5,s6
1cc:   0004203c    dsll32  a0,a0,0x0
1d0:   0004203e    dsrl32  a0,a0,0x0
1d4:   fc950000    sd  s5,0(a0)
1d8:   8f990000    lw  t9,0(gp)
1dc:   0320f809    jalr    t9
1e0:   00008021    move    s0,zero
1e4:   8fbc0010    lw  gp,16(sp)
1e8:   8f990000    lw  t9,0(gp)
1ec:   0320f809    jalr    t9
1f0:   00409821    move    s3,v0
1f4:   8fbc0010    lw  gp,16(sp)
1f8:   afb30064    sw  s3,100(sp)
1fc:   001397c3    sra s2,s3,0x1f
200:   afb20060    sw  s2,96(sp)
204:   8fb10064    lw  s1,100(sp)
208:   afb10068    sw  s1,104(sp)
20c:   afb0006c    sw  s0,108(sp)
210:   8fac0068    lw  t4,104(sp)
214:   afa20074    sw  v0,116(sp)
218:   000277c3    sra t6,v0,0x1f
21c:   afae0070    sw  t6,112(sp)
220:   8faa0074    lw  t2,116(sp)
224:   8fad0070    lw  t5,112(sp)
228:   018d5825    or  t3,t4,t5
 22c:   afab0038    sw  t3,56(sp)
230:   8fa9006c    lw  t1,108(sp)
234:   012a4025    or  t0,t1,t2
238:   afa8003c    sw  t0,60(sp)
23c:   8fa70038    lw  a3,56(sp)
240:   afa7007c    sw  a3,124(sp)
244:   00003021    move    a2,zero
248:   afa60078    sw  a2,120(sp)
24c:   8fa4007c    lw  a0,124(sp)
250:   afa40018    sw  a0,24(sp)
254:   8fa5003c    lw  a1,60(sp)
258:   afa5001c    sw  a1,28(sp)
25c:   8fa30018    lw  v1,24(sp)
260:   8fa2001c    lw  v0,28(sp)
264:   8fa40030    lw  a0,48(sp)
268:   0003183c    dsll32  v1,v1,0x0
26c:   0002103c    dsll32  v0,v0,0x0
270:   0002103e    dsrl32  v0,v0,0x0
274:   00621825    or  v1,v1,v0
278:   0004203c    dsll32  a0,a0,0x0
27c:   0004203e    dsrl32  a0,a0,0x0
280:   fc830000    sd  v1,0(a0)
284:   00001021    move    v0,zero
288:   8fbf00a4    lw  ra,164(sp)
28c:   8fbe00a0    lw  s8,160(sp)
290:   8fb7009c    lw  s7,156(sp)
294:   8fb60098    lw  s6,152(sp)
298:   8fb50094    lw  s5,148(sp)
29c:   8fb40090    lw  s4,144(sp)
2a0:   8fb3008c    lw  s3,140(sp)
2a4:   8fb20088    lw  s2,136(sp)
2a8:   8fb10084    lw  s1,132(sp)
2ac:   8fb00080    lw  s0,128(sp)
2b0:   03e00008    jr  ra
2b4:   27bd00a8    addiu   sp,sp,168

```
<p>可以看到，栈空间一下子由56增加到了168，即增加了112字节这么大的空间！
我们就来分析下这112字节的空间是怎么产生的。<br/>
<1>从汇编代码来看，变量val_high和val_lo仍然是存储在24(sp)和28(sp)这部分内存空间。但是同时也生成了大量的临时变量。<br/>
比如i为1时被展开的循环体：<br/>
```c
f4:   8fb1002c    lw  s1,44(sp) 
  f8:   8fb30028    lw  s3,40(sp) 
  fc:   afb30018    sw  s3,24(sp)
100:   afb1001c    sw  s1,28(sp)  
```
可以看到至少新增了44(sp)和40(sp)这两个临时变量。<br/>
i为2时被展开的循环体：<br/>
```c
1a0:   8fb8005c    lw  t8,92(sp)
1a4:   afb80018    sw  t8,24(sp)
1a8:   8fb70024    lw  s7,36(sp) 
 1ac:   afb7001c    sw  s7,28(sp) 
```
 至少新增了36(sp)和92(sp)这两个临时变量。 <br/>
i为3时被展开的循环体：<br/>
```c
24c:   8fa4007c    lw  a0,124(sp)
250:   afa40018    sw  a0,24(sp)
254:   8fa5003c    lw  a1,60(sp) 
258:   afa5001c    sw  a1,28(sp)  
```
至少新增了60(sp)和124(sp)这两个临时变量。 <br/>
注意这里不是参数入栈和出栈，因为这里是inline，不是函数调用。增加的这六个临时变量都是因为atomic_write64这个inline函数里定义了局部变量，他们其实是为了服务于那两个局部变量。<br/>
<2>再来看变量x <br/>
```c
140:   0320f809    jalr    t9   
144:   00408021    move    s0,v0
148:   8fbc0010    lw  gp,16(sp)
14c:   afb00044    sw  s0,68(sp) 
```
可以看到这里新增加了一个临时变量68(sp)用来存储random()函数的返回值。<br/>
这也是在前面使用“4:   afa40044    sw  a0,68(sp)”来初始化该临时变量的原因。<br/>
<3>循环展开后i值不同的循环体使用不同的$sn寄存器 <br/>
用到这些寄存器，就需要在函数开始将该寄存器压栈，然后在函数结束时出栈。<br/>
```c
  14:   afbe00a0    sw  s8,160(sp)
  18:   afb7009c    sw  s7,156(sp)
  1c:   afb60098    sw  s6,152(sp)
  20:   afb50094    sw  s5,148(sp)
  24:   afb40090    sw  s4,144(sp)
  28:   afb3008c    sw  s3,140(sp)
…  
28c:   8fbe00a0    lw  s8,160(sp)
290:   8fb7009c    lw  s7,156(sp)
294:   8fb60098    lw  s6,152(sp) 
298:   8fb50094    lw  s5,148(sp) 
29c:   8fb40090    lw  s4,144(sp) 
```
新增的这些临时变量和对过多寄存器的使用增加了栈空间，而且入栈出栈也很消耗CPU cycles，因为这涉及到读写内存。 </p>
<p>由此我们可以得到一个初步结论，在unroll-loops的过程中，如果产生了额外的临时变量，那么unroll loops就极有可能对性能造成伤害。 </p>
<p>继续来分析gcc的unroll loops的特性。以下的分析基于gcc的源码loop-unroll.c 。</p>
<p>由于这时TIMES仅为3，gcc可以将其完全展开，即peel_loop_completely，展开方式如下：</p>
```c
/* 
   Peel all iterations of LOOP, remove exit edges and cancel the loop
   completely.  The transformation done:
*/
   for (i = 0; i < 3; i++)
     body;

// 展开为
   i = 0;
   body; i++;
   body; i++;
   body; i++;

```
<p>如果将TIMES增大到100，可以发现gcc并不会将循环体展开100次。循环展开多少次最好，在gcc unroll loops的设计者看来也是一个很难的问题，A great problem is that we don't have a good way how to determine how many times we should unroll the loop; the experiments I have made showed that this choice may affect performance in order of several %. 因而unroll loops的设计着就定义了一些parameter来由程序员自行定义unroll规则。</p>
<p>这些参数有max-unrolled-insns，max-unroll-times，max-peeled-insns和max-peel-times等。用法大致如--param max-unroll-times=N，如果在使能funroll-loops或者fpeel-loops（如果使能了funroll-loops会同时使能fpeel-loops）后没有设置这些参数，就会使用gcc的默认值，具体参考params.def这个文件。 这些参数的具体含义可以去查阅gcc manual，不再赘述。只说下peel和unroll的区别，从英语语义上来讲，peel是剥离，unroll是摊开，在这里也是这个含义，peel是指从循环中给剥离出去，unroll则是仍然在循环体内。我们可以通过gcc的source code来看下这两者的区别。</p>
<p>gcc unroll-loops的入口函数是rtl_unroll_and_peel_loops，在这里它会去检查funroll-loops,fpeel-loops,funroll-all-loops这些开关。然后就会调用unroll loops的主要函数体unroll_and_peel_loops。</p>
```c
     unroll_and_peel_loops
            /* First perform complete loop peeling (it is almost surely a win,
               and affects parameters for further decision a lot).  */
            peel_loops_completely (flags);

            /* Now decide rest of unrolling and peeling.  */
            decide_unrolling_and_peeling (flags);

              /* Scan the loops, inner ones first.  */
            FOR_EACH_LOOP (loop, LI_FROM_INNERMOST)
             {
                  ...
             }

```
<p>可以看到它首先做的就是尝试peel completely，如果不行，就再去选择unroll/peel策略，最后从最内侧循环开始unroll。 举个简单的例子，<br/>
```c
   for (i = 0; i < 102; i++)
     body;

//展开为
   i = 0;
   body; i++;
   body; i++;
   while (i < 102)
     {
       body; i++;
       body; i++;
       body; i++;
       body; i++;
     }

```
前两个body就是peel，后面while循环体内就是unroll。</p> 

<p>总之就是，使用gcc的unroll需谨慎，如果循环次数在编译阶段就确定的，完全可以手动的展开，而不用gcc的unroll，当然展开的次数也是一个经验值，需要根据具体情况来定。对于运行时才能决定循环次数的，gcc也可以将其展开，展开方法大致如下：
<br/>
```c
   for (i = 0; i < n; i++)
     body;

   // 展开为： 
   i = 0;
   mod = n % 4;

   switch (mod)
     {
       case 3:
         body; i++;
       case 2:
         body; i++;
       case 1:
         body; i++;
       case 0: ;
     }

   while (i < n)
     {
       body; i++;
       body; i++;
       body; i++;
       body; i++;
     }

```
另外再说一句，unroll loops要在critical path才能体现出价值来，对于non-critical path，就不应该做unroll loops了。这也是gcc的funroll-loops的一个不足之处，它不知道哪里是critical哪里non-critical，对它而言代码是平等的（程序员主动告知编译器的例外，比如likely/unlikely），它会一视同仁的把所有该展开的都展开。也许编程语言日后的发展方向会是，根据运行时的情况来自动的调整可执行文件的布局，从而每执行一次就可以优化一次来让程序越来越快[3].</p> 

[1] MIPS支持3种ABI：O32/N32/N64,O32/N32的数据模型是ILP32，而N64是LP64，N32和O32的区别是N32的寄存器是64bit而O32的是32bit，N32使用64bits寄存器就要求栈要以8字节对齐。具体见http://math-atlas.sourceforge.net/devel/assembly/007-2816-005.pdf <br/>
[2] 如果返回值是64bits,就会用到$v0和$v1这两个寄存器。对于一些高级编程语言比如Ruby，它可以有多个返回值，不过它实际上是返回的一个数组，数组里面有多个值，即本质上还是返回一个值。<br/>
[3] 支持元编程的语言，比如Ruby，可以在运行时来修改代码，但是它不是来调整代码段的布局。<br/>
