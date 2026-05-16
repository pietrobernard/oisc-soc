library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity uart_RX is
    generic (
        --  uart options
        parity_bit: integer range 0 to 1 := 0;
        parity_typ: integer range 0 to 3 := 0
    );
    port (
        --  systemwide signals
        sysClk:     in  std_logic;
        sysRstb:    in  std_logic;
        --  output data from the RX
        data_from:  out std_logic_vector(7 downto 0);
        data_rdy:   out std_logic;
        data_get:   in  std_logic;
        par_error:  out std_logic;
        --  hardware lines
        serial_in:  in  std_logic;
        enable:     in  std_logic;
        --  uart link parameters
        uart_period:    in std_logic_vector(15 downto 0);
        uart_hperiod:   in std_logic_vector(15 downto 0)
    );
end uart_RX;

architecture Behavioral of uart_RX is
    type t_SM is (s_INIT, s_IDLE, s_START, s_STOP, s_DATA, s_SAMPLE, s_PARITY, s_ERR);
    signal r_stage: t_SM := s_INIT;
    signal serial_in_value: std_logic := '0';
    signal serdata: std_logic := '0';
    signal r_data: std_logic_vector(7 downto 0) := (others => '0');
    signal counter: integer := 0;
    signal bitCounter: integer range 0 to 10 := 0;
    signal bitIndex: integer range 0 to 7 := 0;
    signal r_drdy: std_logic := '0';
    signal r_dget: std_logic := '0';
    signal rdget: std_logic := '0';
    signal packet_parity: std_logic := '0';
    signal r_par_error: std_logic := '0';
    -- link speed
    signal bit_period: integer := 10417;
    signal bit_halfp: integer := 5208;
begin
    --  process SAMPLE: it samples the serial input line
    SAMPLE: process (sysClk)    
            begin
                if (rising_edge(sysClk) and (enable='1')) then
                    serial_in_value <= serial_in;
                    serdata <= serial_in_value;
                    r_dget <= data_get;
                    rdget <= r_dget;
                    bit_period <= to_integer(unsigned(uart_period));
                    bit_halfp <= to_integer(unsigned(uart_hperiod));
                end if;
            end process SAMPLE;
    
    --  process MAIN: it holds the state machine
    MAIN:   process (sysClk)
                variable data_parity: std_logic := '0';
            begin
                if (rising_edge(sysClk) and (enable='1')) then
                    case (r_stage) is
                        --  init stage: waiting for the serial input to fully stabilize
                        when s_INIT =>
                            if (serdata='1') then
                                r_stage <= s_IDLE;
                            else
                                r_stage <= s_INIT;
                            end if;
                        
                        --  idle stage: waiting for an event to occurr on the serial line
                        when s_IDLE =>
                            counter <= 0;
                            bitCounter <= 0;
                            bitIndex <= 0;
                            r_drdy <= '0';
                            r_par_error <= '0';
                            if (serdata='0') then
                                r_stage <= s_START;
                            else
                                r_stage <= s_IDLE;
                            end if;
                        
                        --  start stage: centering on the middle of the start bit
                        when s_START =>
                            -- centering
                            if (counter=(bit_halfp-1)) then
                                counter <= 0;
                                r_stage <= s_SAMPLE;
                            else
                                counter <= counter + 1;
                                r_stage <= s_START;
                            end if;
                        
                        --  data stage: moving ahead of 1 bit period before sampling
                        when s_DATA =>
                            --  moving
                            if (counter=(bit_period-1)) then
                                counter <= 0;
                                r_stage <= s_SAMPLE;
                            else
                                counter <= counter + 1;
                                r_stage <= s_DATA;
                            end if;
                        
                        --  sample stage: sampling the data
                        when s_SAMPLE =>
                            --  sampling
                            if ((bitCounter >= 1) and (bitCounter <= 8)) then
                                r_data(bitIndex) <= serdata;
                                bitCounter <= bitCounter + 1;
                                bitIndex <= bitIndex + 1;
                                r_stage <= s_DATA;
                            elsif (bitCounter=0) then
                                bitCounter <= bitCounter + 1;
                                r_stage <= s_DATA;
                            elsif (bitCounter=9) then
                                bitCounter <= bitCounter + 1;
                                if (parity_bit=1) then
                                    packet_parity <= serdata;
                                    r_stage <= s_PARITY;
                                else
                                    r_stage <= s_STOP;
                                end if;
                            elsif (bitCounter=10) then
                                r_stage <= s_STOP;
                            end if;
                        
                        --  parity check
                        when s_PARITY =>
                            data_parity := r_data(0) xor r_data(1) xor r_data(2) xor r_data(3) xor r_data(4) xor r_data(5) xor r_data(6) xor r_data(7);
                            case (parity_typ) is
                                when 0 =>
                                    --  even parity
                                    --  this means that if the xor of the bits of the data is 0, the parity should be 0
                                    if ((data_parity='0') and (packet_parity='0')) then
                                        r_stage <= s_DATA;
                                    else
                                        r_stage <= s_ERR;
                                    end if;
                                when 1 =>
                                    --  odd parity
                                    --  this means that if the xor of the bits of the data is 0, the parity should be 1
                                    if ((data_parity='0') and (packet_parity='1')) then
                                        r_stage <= s_DATA;
                                    else
                                        r_stage <= s_ERR;
                                    end if;
                                when 2 =>
                                    --  mark parity
                                    --  this means that the parity should be always 1
                                    if (packet_parity='1') then
                                        r_stage <= s_DATA;
                                    else
                                        r_stage <= s_ERR;
                                    end if;
                                when 3 =>
                                    --  space parity
                                    --  this means that the parity should be always 0
                                    if (packet_parity='0') then
                                        r_stage <= s_DATA;
                                    else
                                        r_stage <= s_ERR;
                                    end if;
                            end case;
                        
                        --  stop stage
                        when s_STOP =>
                            if (rdget='1') then
                                r_drdy <= '0';
                                r_stage <= s_IDLE;
                            else
                                r_drdy <= '1';
                                r_stage <= s_STOP;
                            end if;
                        
                        --  err stage
                        when s_ERR =>
                            r_par_error <= '1';
                            r_stage <= s_DATA;
                    end case;
                end if;
            end process MAIN;

    --  assignments
    data_rdy <= r_drdy;
    data_from <= r_data;
    par_error <= r_par_error;   
end Behavioral;
