library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_TX is
    generic (
        --  uart options
        parity_bit: integer range 0 to 1 := 0;  --  0: no parity, 1: parity enabled
        parity_typ: integer range 0 to 3 := 0   --  0: even, 1: odd, 2: mark, 3: space
    );
    port (
        --  systemwide signals
        sysClk:     in  std_logic;
        sysRstb:    in  std_logic;
        --  input data for the TX
        data_to:    in  std_logic_vector (7 downto 0);
        data_send:  in  std_logic;
        data_ok:    out std_logic := '0';
        --  hardware lines
        serial_out: out std_logic := '1';
        enable:     in  std_logic;
        --  uart link parameters
        uart_period:    in std_logic_vector(15 downto 0);
        uart_hperiod:   in std_logic_vector(15 downto 0)
    );
end uart_TX;

architecture Behavioral of uart_TX is
    --  state machine type and signal
    type t_SM is (s_IDLE, s_TX, s_CHECK, s_STOP, s_PARGEN);
    signal r_stage: t_SM := s_IDLE;      
    --  signals for the data to transmit and the command  
    signal  tx_data:    std_logic_vector(10 downto 0) := (others => '0');
    signal  tx_command: std_logic := '0';    
    --  drive signal and status signals
    signal  r_sout: std_logic := '1';
    signal  r_dok: std_logic := '0';        
    signal  r_parity_bit: std_logic := '0';
    --  signals that holds the various counters
    signal  r_counter:  integer := 0;
    signal  r_bitcount: integer := 0;
    -- link speed
    signal bit_period: integer := 10417;
    signal bit_halfp: integer := 5208;
begin
    SAMPLE: process (sysClk)
    
            begin
                if (rising_edge(sysClk) and (enable='1')) then
                    tx_data(0) <= '0';              --  start bit
                    tx_data(8 downto 1) <= data_to; --  data bits
                    tx_data(9) <= r_parity_bit;     --  parity bit (if present)
                    tx_data(10) <= '1';             --  stop bit
                    tx_command <= data_send;
                    bit_period <= to_integer(unsigned(uart_period));
                    bit_halfp <= to_integer(unsigned(uart_hperiod));
                end if;
            end process SAMPLE;

    MAIN:   process (sysClk)
                variable data_parity:   std_logic := '0';
            begin
                if (rising_edge(sysClk) and (enable='1')) then
                    case (r_stage) is
                        --  waiting for a command to send data
                        when s_IDLE =>
                            if (tx_command='1') then
                                r_stage <= s_TX;
                            else
                                r_stage <= s_IDLE;
                                r_sout <= '1';
                                r_counter <= 0;
                                r_bitcount <= 0;
                                r_dok <= '0';
                            end if;
                        
                        --  sending a bit
                        when s_TX =>                            
                            if (r_counter=(bit_period-1)) then
                                r_counter <= 0;
                                r_stage <= s_CHECK;
                                --r_bitcount <= r_bitcount + 1;                            
                            else
                                r_sout <= tx_data(r_bitcount);
                                r_stage <= s_TX;
                                r_counter <= r_counter + 1;
                            end if;
                    
                        --  checking
                        when s_CHECK =>
                            r_counter <= 0;
                            if (r_bitcount=8) then
                                --  start bit + data bits have been sent, so checking parity
                                if (parity_bit=1) then
                                    --  need to calculate parity
                                    r_bitcount <= r_bitcount + 1;
                                    r_stage <= s_PARGEN;
                                else
                                    --  no parity, so I need to skip the parity bit and go to the stop bit
                                    r_bitcount <= r_bitcount + 2;
                                    r_stage <= s_TX;
                                end if;
                            elsif (r_bitcount=10) then
                                --  need to stop
                                r_dok <= '1';                                                                
                                r_stage <= s_STOP;
                            else
                                --  need to send the next bit
                                r_bitcount <= r_bitcount + 1;
                                r_stage <= s_TX;
                            end if;
                    
                        --  stop
                        when s_STOP =>
                            if (tx_command='0') then
                                r_stage <= s_IDLE;
                            else
                                r_stage <= s_STOP;
                            end if;
                        
                        --  parity generator
                        when s_PARGEN =>
                            data_parity := tx_data(1) xor tx_data(2) xor tx_data(3) xor tx_data(4) xor tx_data(5) xor tx_data(6) xor tx_data(7) xor tx_data(8);
                            case (parity_typ) is
                                when 0 =>
                                    --  even parity
                                    if data_parity='0' then
                                        r_parity_bit <= '0';
                                    else
                                        r_parity_bit <= '1';
                                    end if;
                                when 1 =>
                                    --  odd parity
                                    if data_parity='0' then
                                        r_parity_bit <= '1';
                                    else
                                        r_parity_bit <= '0';
                                    end if;
                                when 2 =>
                                    -- mark parity
                                    r_parity_bit <= '1';
                                when 3 =>
                                    --  space parity
                                    r_parity_bit <= '0';
                            end case;
                            r_stage <= s_TX;
                            
                    end case;
                end if;
            end process MAIN;

    --  assignments
    serial_out <= r_sout;
    data_ok <= r_dok;
end Behavioral;
