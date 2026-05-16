library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  this module should allow for 'autosensing' the link speed when the user sends a synchronization
--  symbol that is code 10101010, 170 or 0xAA. In this way the link speed can be adjusted without having to recompile the component.
--  standard uart speeds: 9600, 19200, 57600, 115200, 256000
--  this roughly converts to:
--  speed   |   packet_bits |   data bit rate
--  9600    |   10          |   0.8*9600 = 7680, or 960 bytes/s, 0.9375 kbytes/s
--  19200   |   10          |   0.8*19200 = 15360, or 1920 bytes/s, 1.875 kbytes/s
--  57600   |   10          |   0.8*57600 = 46080, or 5760 bytes/s, 5.625 kbytes/s
--  115200  |   10          |   0.8*115200 = 92160, or 11520 bytes/s, 11,25 kbytes/s
--  256000  |   10          |   0.8*256000 = 204800, or 25600 bytes/s, 25 kbytes/s
entity uart_SYNC is
    port (
        --  systemwide signals
        sysClk:         in  std_logic;
        sysRstb:        in  std_logic;
        --  input data for the TX
        O_fullperiod:   out std_logic_vector(15 downto 0);
        O_halfperiod:   out std_logic_vector(15 downto 0);
        syncOK:         out std_logic;
        --  hardware lines
        serial_in:      in  std_logic
    );
end uart_SYNC;

architecture Behavioral of uart_SYNC is
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_START, s_HALFP, s_HHALFP, s_SYNC, s_WAIT_LOW, s_WAIT_HIGH);
    signal r_stage: t_SM := s_INIT;
    --  other signals
    signal r_sin: std_logic := '0';
    signal r_count: integer range 0 to 65535  := 0;
    signal r_hcount: integer range 0 to 65535 := 0;
    signal r_hhcount: integer range 0 to 65535 := 0;
    signal r_hdiff: integer range 0 to 65535 := 0;
    signal r_diff: integer range 0 to 65535 := 0;
    signal r_sync: std_logic := '0';
    signal n_trans: natural := 0;
begin
    --  sample process to get the data from the serial line
    SAMPLE: process(sysClk)
            
            begin
                if (rising_edge(sysClk)) then
                    r_sin <= serial_in;
                end if;
            end process SAMPLE;

    --  main process to run the synchronization
    MAIN:   process(sysClk)
            begin
                if (rising_edge(sysClk)) then
                    r_diff <= r_count - r_hcount;
                    r_hdiff <= r_hcount - r_hhcount;
                    case (r_stage) is
                        --  waits for the serial line to stabilize at logic HIGH that is the idling condition
                        when s_INIT =>
                            r_count <= 0;
                            r_hcount <= 0;
                            r_sync <= '0';
                            n_trans <= 0;
                            r_hhcount <= 0;
                            if (r_sin='1') then
                                r_stage <= s_IDLE;
                            else
                                r_stage <= s_INIT;
                            end if;
                        --  waits for an event to occurr to calculate the bit period
                        when s_IDLE =>
                            if (r_sin='0') then
                                n_trans <= n_trans + 1;
                                r_stage <= s_START;
                            else
                                r_stage <= s_IDLE;
                            end if;
                        --  now: i should have 1 start bit, 8 data bits, 0 or 1 parity, 1 stop bit so: 10 to 11 bits in the whole period.
                        when s_START =>
                            if (r_sin='1') then
                                r_stage <= s_WAIT_HIGH;
                            else
                                r_count <= r_count + 1;
                                r_stage <= s_START;
                            end if;
                        -- now: calculating the half period -> needs a little trick
                        -- suppose N is the full period and H is the half period, i have to increment H until N-H equals H
                        when s_HALFP =>
                            if ((r_diff=r_hcount) or (r_diff=(r_hcount-1)) or (r_diff=(r_hcount+1))) then
                                r_stage <= s_HHALFP;
                            else
                                r_hcount <= r_hcount + 1;
                                r_stage <= s_HALFP;
                            end if;
                        when s_HHALFP =>
                            if ((r_hdiff=r_hhcount) or (r_hdiff=(r_hhcount-1)) or (r_hdiff=(r_hhcount+1))) then
                                r_stage <= s_SYNC;
                            else
                                r_hhcount <= r_hhcount + 1;
                                r_stage <= s_HHALFP;
                            end if;
                        --  full and half periods have been obtained, so:
                        when s_SYNC =>
                            r_sync <= '1';
                            r_stage <= s_SYNC;
                        --  waiting for the packet to end
                        when s_WAIT_HIGH =>
                            if (r_sin='0') then
                                n_trans <= n_trans + 1;
                                r_stage <= s_WAIT_LOW;
                            else
                                r_stage <= s_WAIT_HIGH;
                            end if;
                        when s_WAIT_LOW =>
                            if (r_sin='1') then
                                if ((n_trans=5) or (n_trans=6)) then
                                    r_stage <= s_HALFP;
                                else
                                    r_stage <= s_WAIT_HIGH;
                                end if;
                            else
                                r_stage <= s_WAIT_LOW;
                            end if;
                    end case;
                end if;
            end process MAIN;

    --  assignment 
    syncOK <= r_sync;
    O_fullperiod <= std_logic_vector(to_unsigned(r_hcount, O_fullperiod'length));
    O_halfperiod <= std_logic_vector(to_unsigned(r_hhcount, O_halfperiod'length));
end Behavioral;
