#
# Copyright (C) 2019-2020 INTI
# Copyright (C) 2019-2020 Rodrigo A. Melo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

"""fpga.tool.ise

Implements the support of ISE (Xilinx).
"""

import os
import re

from fpga.tool import Tool, run

_TEMPLATES = {
    'fpga': """setMode -bs
setCable -port auto
Identify -inferir
assignFile -p #POSITION# -file #BITSTREAM#
Program -p #POSITION#

quit
""",
    'spi': """setMode -pff
addConfigDevice -name #NAME# -path .
setSubmode -pffspi
addDesign -version 0 -name 0
addDeviceChain -index 0
addDevice -p 1 -file #BITSTREAM#
generate -generic

setMode -bs
setCable -port auto
Identify
attachflash -position #POSITION# -spi #NAME#
assignfiletoattachedflash -position #POSITION# -file ./#NAME#.mcs
Program -p #POSITION# -dataWidth #WIDTH# -spionly -e -v -loadfpga

quit
""",
    'bpi': """setMode -pff
addConfigDevice -name #NAME# -path .
setSubmode -pffbpi
addDesign -version 0 -name 0
addDeviceChain -index 0
setAttribute -configdevice -attr flashDataWidth -value #WIDTH#
addDevice -p 1 -file #BITSTREAM#
generate -generic

setMode -bs
setCable -port auto
Identify
attachflash -position #POSITION# -bpi #NAME#
assignfiletoattachedflash -position #POSITION# -file ./#NAME#.mcs
Program -p #POSITION# -dataWidth #WIDTH# \
-rs1 NONE -rs0 NONE -bpionly -e -v -loadfpga

quit
""",
    'detect': """setMode -bs
setCable -port auto
Identify -inferir
quit
""",
    'unlock': """cleancablelock
quit
"""
}


class Ise(Tool):
    """Implementation of the class to support ISE."""

    _TOOL = 'ise'
    _EXTENSION = 'xise'
    _PART = 'xc7k160t-3-fbg484'

    _GEN_COMMAND = 'xtclsh ise.tcl'
    _TRF_COMMAND = 'impact -batch ise-prog.impact'

    _BIT_EXT = ['bit']
    _DEVTYPES = ['fpga', 'spi', 'bpi', 'detect', 'unlock']

    _GENERATED = [
        # directories
        'iseconfig', '_ngo', 'xlnx_auto_0_xdb', '_xmsgs', 'xst',
        # files
        '*.bgn', '*.bld', '*.bit',
        '*.cmd_log', '*.csv',
        '*.drc',
        '*.gise',
        '*.html',
        '*.log', '*.lso',
        '*.map', '*.mrp',
        '*.ncd', '*.ngc', '*.ngd', '*.ngm', '*.ngr',
        '*.pad', '*.par', '*.pcf', '*.prj', '*.ptwx',
        '*.stx', '*.syr',
        '*.twr', '*.twx',
        '*.unroutes', '*.ut',
        '*.txt',
        '*.xml', '*.xpi', '*.xrpt', '*.xst', '*.xwbt',
        '_impact*',
        'ise.tcl'
    ]

    def __init__(self, project, frontend=None):
        super().__init__(project)
        # pylint: disable=import-outside-toplevel
        if frontend == 'yosys':
            from fpga.tool.yosys import Yosys
            self.tool = Yosys(self.project, 'edif-ise')
            self.presynth = True

    def set_part(self, part):
        try:
            family, speed, package = re.findall(r'(\w+)-(\w+)-(\w+)', part)[0]
            if len(speed) > len(package):
                speed, package = package, speed
            part = "{}-{}-{}".format(family, speed, package)
        except IndexError:
            raise ValueError(
                'Part must be FAMILY-SPEED-PACKAGE or FAMILY-PACKAGE-SPEED'
            )
        self.part = part

    def set_param(self, name, value):
        if self.presynth:
            self.tool.set_param(name, value)
        else:
            super().set_param(name, value)

    def add_file(self, file, library=None, included=False, design=False):
        ext = os.path.splitext(file)[1]
        if self.presynth and ext in ['.v', '.sv', '.vh', '.vhd', '.vhdl']:
            self.tool.add_file(file, library, included, design)
        elif not design:
            super().add_file(file, library, included, design)

    def generate(self, strategy, to_task, from_task, capture):
        if self.presynth and from_task == 'prj':
            self.tool.set_part(self.part)
            self.tool.set_top(self.top)
            output1 = self.tool.generate(strategy, 'syn', 'prj', capture)
            self.add_file('{}.edif'.format(self.project))
            output2 = super().generate(strategy, to_task, from_task, capture)
            return str(output1) + str(output2)
        return super().generate(strategy, to_task, from_task, capture)

    def transfer(self, devtype, position, part, width, capture):
        super().transfer(devtype, position, part, width, capture)
        temp = _TEMPLATES[devtype]
        if devtype not in ['detect', 'unlock']:
            temp = temp.replace('#BITSTREAM#', self.bitstream)
            temp = temp.replace('#POSITION#', str(position))
            temp = temp.replace('#NAME#', part)
            temp = temp.replace('#WIDTH#', str(width))
        open("ise-prog.impact", 'w').write(temp)
        return run(self._TRF_COMMAND, capture)
