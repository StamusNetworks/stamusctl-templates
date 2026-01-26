#!/usr/bin/python3

# Written by  Gabor Seljan
# Modified by Raphaël Brogat to include this copyright notice
# Modified to run as foreground process for Docker containerization
#
# This script comes with ABSOLUTELY NO WARRANTY!
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
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

"""
Helper script for the Scirius project to reload rules.
Runs in foreground mode suitable for Docker containers.
"""

import os
import sys
import time
import logging

from suricata.sc import SuricataSC, SuricataNetException, SuricataReturnException

RELOAD_PATH = '/rules/scirius.reload'
SOCKET_PATH = os.getenv('SURICATA_UNIX_SOCKET', '/var/run/suricata.socket')
CHECK_INTERVAL = 1  # seconds

def setup_logging():
    """Configure logging to stdout for Docker log collection"""
    logging.basicConfig(
        stream=sys.stdout,
        format='%(asctime)s [%(levelname)s] %(message)s',
        level=logging.INFO)
    return logging.getLogger('suri_reloader')

def reload_rules(logger):
    """Main loop to monitor and reload Suricata rules"""
    logger.info('Starting Suricata rule reloader')
    logger.info('Monitoring reload trigger at: %s', RELOAD_PATH)
    logger.info('Suricata socket path: %s', SOCKET_PATH)
    logger.info('Check interval: %d second(s)', CHECK_INTERVAL)

    consecutive_errors = 0
    max_consecutive_errors = 5

    while True:
        try:
            time.sleep(CHECK_INTERVAL)

            if os.path.isfile(RELOAD_PATH):
                logger.info('Reload trigger detected - initiating ruleset reload')

                sc = SuricataSC(SOCKET_PATH)
                try:
                    logger.debug('Connecting to Suricata socket...')
                    sc.connect()
                    logger.debug('Connection established, negotiating version')

                except SuricataNetException as err:
                    logger.error('Unable to connect to socket %s: %s', SOCKET_PATH, err)
                    consecutive_errors += 1
                    if consecutive_errors >= max_consecutive_errors:
                        logger.critical('Too many consecutive connection errors (%d), exiting',
                                      consecutive_errors)
                        sys.exit(1)
                    continue

                except SuricataReturnException as err:
                    logger.error('Unable to negotiate version with Suricata: %s', err)
                    consecutive_errors += 1
                    if consecutive_errors >= max_consecutive_errors:
                        logger.critical('Too many consecutive negotiation errors (%d), exiting',
                                      consecutive_errors)
                        sys.exit(1)
                    continue

                logger.info('Sending reload-rules command to Suricata')
                res = sc.send_command('reload-rules')
                sc.close()

                if res['return'] == 'OK':
                    try:
                        os.unlink(RELOAD_PATH)
                        logger.info('Ruleset successfully reloaded')
                        consecutive_errors = 0  # Reset error counter on success
                    except OSError as err:
                        logger.warning('Failed to remove reload trigger file: %s', err)
                else:
                    logger.error('Suricata returned error during reload: %s', res.get('message', 'unknown'))
                    consecutive_errors += 1

        except KeyboardInterrupt:
            logger.info('Received interrupt signal, shutting down gracefully')
            sys.exit(0)

        except Exception as err:
            logger.exception('Unexpected error in main loop: %s', err)
            consecutive_errors += 1
            if consecutive_errors >= max_consecutive_errors:
                logger.critical('Too many consecutive errors (%d), exiting', consecutive_errors)
                sys.exit(1)
            time.sleep(5)  # Back off on unexpected errors

if __name__ == "__main__":
    logger = setup_logging()
    try:
        reload_rules(logger)
    except Exception as err:
        logger.critical('Fatal error: %s', err, exc_info=True)
        sys.exit(1)
