# ============================================================================
#  libs/env_synopsys.sh -- bash equivalent of ~/source_me.sh (which is csh)
#
#     source libs/env_synopsys.sh
#
#  Puts dc_shell / vcd2saif on PATH and sets the ASU license server.
# ============================================================================

export SYNOPSYS=/usr/local/tools/Synopsys
export SNPSLMD_LICENSE_FILE=27020@enlicense5.eas.asu.edu
export LM_LICENSE_FILE=27020@enlicense5.eas.asu.edu

# Design Compiler 2023.12-SP5 (also provides vcd2saif)
export PATH=$SYNOPSYS/syn/V-2023.12-SP5/bin:$PATH
# PrimeTime / PrimePower, if you want sign-off timing or power later
export PATH=$SYNOPSYS/prime2022/T-2022.03-SP5-5/bin:$PATH
# VCS, if you prefer it over Icarus for the SAIF workload
export VCS_HOME=$SYNOPSYS/vcs/U-2023.03-SP2-8
export VCS_TARGET_ARCH=linux64
export PATH=$VCS_HOME/bin:$PATH
