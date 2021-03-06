"""PyFPGA Multi Vendor VHDL example.

The main idea of a multi-vendor project is to implements the same HDL code
with different tools, to make comparisons. The project name is not important
and the default devices are used.
"""

import logging

from fpga.project import Project, TOOLS

logging.basicConfig()

for tool in TOOLS:
    PRJ = Project(tool)
    PRJ.set_outdir('../../build/multi/vhdl/%s' % tool)
    PRJ.add_files('../../hdl/blinking.vhdl', library='examples')
    PRJ.add_files('../../hdl/examples_pkg.vhdl', library='examples')
    PRJ.add_files('../../hdl/top.vhdl')
    PRJ.set_top('Top')
    try:
        PRJ.generate(to_task='syn')
    except RuntimeError:
        print('ERROR:generate:{} not found'.format(tool))
