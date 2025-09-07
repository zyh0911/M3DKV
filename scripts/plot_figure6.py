#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import matplotlib.patches as mpatches
import matplotlib.lines   as mlines
import matplotlib.ticker as mticker
import numpy as np

plt.rcParams.update({
    'font.size'       : 28,
    'axes.labelsize'  : 28,
    'axes.labelweight': 'bold',
    'xtick.labelsize' : 28,
    'ytick.labelsize' : 28,
    'legend.fontsize' : 28,
})

# ───────────────────────────────────────────────
# 1.  table & functions
# ───────────────────────────────────────────────
decoder_power_table = {
     8: 5.20e-04,  16: 1.29e-03,  32: 2.02e-03,  48: 2.46e-03,
    64: 3.04e-03,  96: 4.08e-03, 128: 4.94e-03, 192: 5.63e-03,
   256: 7.35e-03, 384: 9.12e-03
}
adder_tree_area          = {2: 2296.34, 4: 1038.4920, 8: 485.35, 16: 231.46}
round_max_table_area     = {16: 598.75, 32: 364.14, 64: 248.97, 128: 180.13}
softmax_block3_table_area = {
    (16, 2): 7319.97, (32, 2): 3905.2439, (64, 2): 2108.8620, (128, 2): 1210.86,
    (16, 4): 7313.29, (32, 4): 3901.7159, (64, 4): 2110.2480, (128, 4): 1209.3480,
    (16, 8): 7316.69, (32, 8): 3901.7159, (64, 8): 2111.5080, (128, 8): 1213.2540,
    (16,16): 7309.76, (32,16): 3899.5739, (64,16): 2109.4920, (128,16): 1207.9620
}
pre_align_reuse_area = {
    (16, 2): 3921.8760, (32, 2): 3797.1839, (64, 2): 3925.53,  (128, 2): 3892.14,
    (16, 4): 1827.1260, (32, 4): 1863.1626, (64, 4): 1847.03,  (128, 4): 1843.25,
    (16, 8): 911.8620,  (32, 8): 920.1780,  (64, 8): 901.53,   (128, 8): 921.8160,
    (16,16): 436.84,    (32,16): 432.684,   (64,16): 427.64,   (128,16): 426.384
}
pre_align_area = {
    (16, 2): 540.6660, (32, 2): 541.422,   (64, 2): 511.3080, (128, 2): 513.576,
    (16, 4): 257.1660, (32, 4): 253.890,   (64, 4): 255.9060, (128, 4): 264.474,
    (16, 8): 133.6860, (32, 8): 130.284,   (64, 8): 130.284,  (128, 8): 132.3,
    (16,16): 63.756,   (32,16): 63.756,    (64,16): 63.756,   (128,16): 63.756
}
adder_tree_power          = {2: 0.722, 4: 0.326, 8: 0.160, 16: 8.17e-02}
round_max_table_power     = {16: 2.52e-02, 32: 3.18e-02, 64: 1.71e-02, 128: 1.46e-02}
softmax_block3_table_power = {
    (16, 2): 2.998,  (32, 2): 1.474, (64, 2): 0.765, (128, 2): 0.409,
    (16, 4): 2.998,  (32, 4): 1.475, (64, 4): 0.765, (128, 4): 0.409,
    (16, 8): 2.999,  (32, 8): 1.474, (64, 8): 0.765, (128, 8): 0.409,
    (16,16): 2.999,  (32,16): 1.450, (64,16): 0.765, (128,16): 0.409
}
pre_align_power = {
    (16, 2): 4.66e-02, (32, 2): 4.63e-02, (64, 2): 4.44e-02, (128, 2): 4.60e-02,
    (16, 4): 2.82e-02, (32, 4): 2.86e-02, (64, 4): 2.80e-02, (128, 4): 2.92e-02,
    (16, 8): 2.05e-02, (32, 8): 1.99e-02, (64, 8): 2.08e-02, (128, 8): 2.06e-02,
    (16,16): 1.61e-02, (32,16): 1.62e-02, (64,16): 1.62e-02, (128,16): 1.59e-02
}
pre_align_reuse_power = {
    (16, 2): 0.776, (32, 2): 0.766, (64, 2): 0.780, (128, 2): 0.768,
    (16, 4): 0.376, (32, 4): 0.382, (64, 4): 0.382, (128, 4): 0.383,
    (16, 8): 0.185, (32, 8): 0.194, (64, 8): 0.189, (128, 8): 0.195,
    (16,16): 9.83e-02, (32,16): 9.89e-02, (64,16): 9.98e-02, (128,16): 9.94e-02
}

BANK_ROWS, BANK_COLUMNS = 1024, 1536
CELL_AREA        = 4 * 75 * 75 / 1e6   # μm²
BASE_LAYER_SCALE = 1.5

def decoder_transistor_count(N: int) -> int:
    T_UNIT = 86
    total_units, mk = 0, -(-N // 8)
    while True:
        total_units += mk
        if mk == 1:
            break
        mk = -(-mk // 8)
    return total_units * T_UNIT

# ───────────────────────────────────────────────
# 2.  area/power/efficiency/performance
# ───────────────────────────────────────────────
def cache_layer_area(m, n):
    channel, width = BANK_ROWS / m, BANK_COLUMNS / n
    macro_num = channel * width
    periph = (8/2 + 4*n/2 + 4/2 + 16/1.5) / 2 * CELL_AREA * BASE_LAYER_SCALE * macro_num
    mem_arr = m * n * CELL_AREA * BASE_LAYER_SCALE * macro_num
    dec = (decoder_transistor_count(m) + decoder_transistor_count(n)) / 2 * CELL_AREA * BASE_LAYER_SCALE * macro_num
    return 2 * (periph + mem_arr + dec)

def base_layer_area(m, n):
    channel = BANK_ROWS / m
    macro_col_acc = channel * 403.2
    control = 114.9120 + 386.4420 + 26.8380
    gemv1 = pre_align_area[(m, n)] * (channel - 1) + pre_align_reuse_area[(m, n)]
    gemv2 = (305.9280 + adder_tree_area[n] + 279.7200) * channel
    sfx1 = round_max_table_area[m] + (64/n) * (338.5 + 933)
    sfx2 = 1015.5600 + (64/n) * 338.5
    sfx3 = softmax_block3_table_area[(m, n)]
    return gemv1 + gemv2 + 2*control + 2*macro_col_acc + sfx1 + sfx2 + sfx3

def cache_layer_power(m, n):
    channel, width = BANK_ROWS / m, BANK_COLUMNS / n
    macro_num = channel * width
    macro = (1.177 + 1.05 + 1.067 + 1.096) / 4 * 1.2 * 0.9 * macro_num / 1000
    dec   = (decoder_power_table[m] + decoder_power_table[n]) * 28*28/75/75 * macro_num
    return 2 * (macro + dec)

def base_layer_power(m, n):
    channel = BANK_ROWS / m
    macro_col_acc = channel * 5.53e-02
    control = 0.233 + 5.80e-03 + 1.03e-02
    gemv1 = pre_align_power[(m, n)] * (channel - 1) + pre_align_reuse_power[(m, n)]
    gemv2 = (7.1e-02 + adder_tree_power[n] + 4.98e-02) * channel
    sfx1 = round_max_table_power[m] + (64/n) * (4.59e-02 + 0.123)
    sfx2 = 0.224 + (64/n) * 2.75e-02
    sfx3 = softmax_block3_table_power[(m, n)]
    return gemv1 + gemv2 + 2*control + 2*macro_col_acc + sfx1 + sfx2 + sfx3

def area_efficiency(m, n, area_mm2):
    return (1024/m * 64/n / 9) * 2 * 5e8 / 1e12 / (area_mm2/2)

def memory_density(area_mm2):
    return 2 * BANK_COLUMNS * BANK_ROWS * 16 / (1024 * 1024 * 8) / area_mm2

def performance(m, n):
    v_m, v_n = m / 16, 16 * n
    gemv1_cycles = (9 * n) * m + 1024/m
    gemv2_cycles = 24 * v_m + (9 * v_n) * v_m + 207
    time_ms = (gemv1_cycles + gemv2_cycles) * 2 / 1e6
    return 0.509 / time_ms           # speed-up

# ───────────────────────────────────────────────
# 3.  design point
# ───────────────────────────────────────────────
m_vals, n_vals = np.array([16,32,64]), np.array([2,4,8,16])
labels, md_vals, ae_vals, eapp_vals, speed_vals = [], [], [], [], []
base_areas, cache_areas = [], []
for m in m_vals:
    for n in n_vals:
        labels.append(f"{m}-{n*24:02d}")
        b_area = base_layer_area(m,n)/1e6
        c_area = cache_layer_area(m,n*24)/1e6
        area_mm2 = max(b_area,c_area)
        pwr_mW   = cache_layer_power(m,n*24)*10 + base_layer_power(m,n)
        md_vals.append(memory_density(area_mm2))
        ae_vals.append(area_efficiency(m,n,area_mm2))
        eapp_vals.append(ae_vals[-1]/pwr_mW*1e3)
        speed_vals.append(performance(m,n))
        base_areas.append(b_area); cache_areas.append(c_area)

md_vals, ae_vals = np.array(md_vals), np.array(ae_vals)
eapp_vals, speed_vals = np.array(eapp_vals), np.array(speed_vals)

# ───────────────────────────────────────────────
# 4.  scale & helpers
# ───────────────────────────────────────────────
width, group_gap = 0.3, 0.75
x_base = np.arange(len(labels))*group_gap

def lighten(color,ratio=0.4):
    rgb=np.array(mcolors.to_rgb(color))
    return tuple(rgb*ratio+(1-ratio))

def add_gridlines(ax, n_major=6, n_minor=1):
    ymin, ymax = ax.get_ylim()
    ax.set_yticks(np.linspace(ymin, ymax, n_major+1))
    ax.set_yticklabels([])
    ax.tick_params(axis='y', length=0)       
    ax.grid(axis='y', which='major', ls=':', lw=1.5, zorder=0)
    if n_minor > 0:
        ax.yaxis.set_minor_locator(mticker.LinearLocator((n_major+1)*(n_minor+1)))
        ax.grid(axis='y', which='minor', ls=':', lw=1.5, alpha=0.7, zorder=0)

# ───────────────────────────────────────────────
# 5. plot
# ───────────────────────────────────────────────
fig,(ax_top,ax_mid_left,ax_bot_left)=plt.subplots(
    3,1,sharex=True,figsize=(25,16),
    gridspec_kw={'height_ratios':[1,1.2,1.2],'hspace':0.05})

# Row-1：Area 折线及数值 -----------------------
ax_top.plot(x_base,base_areas ,marker='o',lw=4,color='#0000FF',
            label='Base Layer Area (mm²)')
ax_top.plot(x_base,cache_areas,marker='x',lw=4,ls='--',color='#0000FF',
            label='Cache Layer Area (mm²)')
ax_top.set_ylim(0,max(base_areas+cache_areas)*1.05)
add_gridlines(ax_top, n_major=6, n_minor=0)    

for x, b, c in zip(x_base, base_areas, cache_areas):
    if b >= c:
        ax_top.annotate(f"{b:.2f}", xy=(x, b), xytext=(0,  8),
                        textcoords='offset points', ha='center',
                        va='bottom', fontsize=20)
        ax_top.annotate(f"{c:.2f}", xy=(x, c), xytext=(0, -12),
                        textcoords='offset points', ha='center',
                        va='top', fontsize=20)
    else:
        ax_top.annotate(f"{b:.2f}", xy=(x, b), xytext=(0, -12),
                        textcoords='offset points', ha='center',
                        va='top', fontsize=20)
        ax_top.annotate(f"{c:.2f}", xy=(x, c), xytext=(0,  8),
                        textcoords='offset points', ha='center',
                        va='bottom', fontsize=20)

# Row-2：AE & MD ------------------------------
bars_ae = ax_mid_left.bar(x_base+0.5*width, ae_vals, width=width,
                          color='#2aa7de',ec='#2aa7de',zorder=3)
ax_mid_left.set_ylim(0,ae_vals.max()*1.05)
add_gridlines(ax_mid_left, n_major=6, n_minor=0)  

ax_mid_right = ax_mid_left.twinx()
bars_md = ax_mid_right.bar(x_base-0.5*width, md_vals, width=width,
                           color='#6e3fc1',ec='#6e3fc1',zorder=3)
ax_mid_right.set_ylim(0,md_vals.max()*1.05)
ax_mid_right.set_yticklabels([])                   
ax_mid_right.tick_params(axis='y', length=0)

# Row-3：EAPP & Speed-up -----------------------
bars_eapp = ax_bot_left.bar(x_base+0.5*width, eapp_vals, width=width,
                            color='#026534',ec='#026534',zorder=3)
ax_bot_left.set_ylim(0,eapp_vals.max()*1.05)
add_gridlines(ax_bot_left, n_major=6, n_minor=0) 

ax_bot_right = ax_bot_left.twinx()
bars_spd  = ax_bot_right.bar(x_base-0.5*width, speed_vals, width=width,
                             color='#ca0e12',ec='#ca0e12',zorder=3)
ax_bot_right.set_ylim(0,speed_vals.max()*1.05)
ax_bot_right.set_yticklabels([])
ax_bot_right.tick_params(axis='y', length=0)

# x-axis
ax_bot_left.set_xticks(x_base)
ax_bot_left.set_xticklabels(labels,rotation=45,ha='right')
ax_bot_left.set_xlabel('m–n (macro rows–macro columns)',labelpad=10)

# =========== highlight ===========
selected={'16-48','32-96','64-48','64-192'}
for i,lbl in enumerate(labels):
    if lbl not in selected:
        for bars in (bars_ae,bars_md,bars_eapp,bars_spd):
            if i<len(bars):
                c=bars[i].get_facecolor()
                bars[i].set_facecolor(lighten(c))
                bars[i].set_edgecolor(lighten(c))

for i in range(1,len(np.unique(m_vals))):
    pos=(i*len(n_vals)-0.5)*group_gap
    for ax in (ax_top,ax_mid_left,ax_mid_right,ax_bot_left,ax_bot_right):
        ax.axvline(pos,color='grey',linestyle=':',linewidth=2,zorder=0)

fig.tight_layout(rect=[0,0.12,1,0.96])
for ax in (ax_top,ax_mid_left,ax_bot_left):
    ax.margins(x=0.005)

# ===== output =====
fig.savefig('dse_v4.pdf', format='pdf')
print('dse_v4.pdf generated')
