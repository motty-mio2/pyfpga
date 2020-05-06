"""ISE example project."""

import argparse
import logging

from fpga.project import Project

logging.basicConfig()
logging.getLogger('fpga.project').level = logging.DEBUG

parser = argparse.ArgumentParser()
parser.add_argument(
    '--action', choices=['generate', 'transfer', 'all'], default='generate',
)
args = parser.parse_args()

prj = Project('ise')
prj.set_part('XC6SLX9-2-CSG324')

prj.set_outdir('../../build/ise')

prj.add_files('../../hdl/blinking.vhdl', 'examples')
prj.add_files('../../hdl/examples_pkg.vhdl', 'examples')
prj.add_files('../../hdl/top.vhdl')
prj.set_top('Top')
prj.add_files('s6micro.xcf')
prj.add_files('s6micro.ucf')

if args.action in ['generate', 'all']:
    try:
        prj.generate()
    except Exception as e:
        logging.warning('{} ({})'.format(type(e).__name__, e))

if args.action in ['transfer', 'all']:
    try:
        prj.transfer('fpga')
        #  prj.transfer('detect')
        #  prj.transfer('unlock')
        #  prj.transfer('spi', 1, 'N25Q128', 4)
    except Exception as e:
        logging.warning('ERROR: {} ({})'.format(type(e).__name__, e))