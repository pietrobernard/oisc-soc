library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity uart_trx is
    generic (
        data_bit:       integer := 8;               --  number of data bits: 8
        parity_bit:     integer range 0 to 1 := 0;  --  number of parity bits: 0 or 1
        stop_bit:       integer range 0 to 1 := 0;  --  number of stop bits: 1 or 2
        parity_typ:     integer range 0 to 3 := 0;  --  type of parity: 0 even, 1 odd, 2 mark, 3 space
        link_speed:     integer := 9600
    );
    port (
        sysClk:         in std_logic;
        sysRstb:        in std_logic;
        --  uart lines
        serial_input:   in std_logic;
        serial_output:  out std_logic;
        --  input side
        data_in:        in std_logic_vector(7 downto 0);
        data_tx:        in std_logic;
        data_tx_done:   out std_logic;
        --  output side
        data_out:       out std_logic_vector(7 downto 0);
        data_rx:        out std_logic;
        data_rx_ack:    in std_logic;
        --  debug
        rx_stage_dbg:   out std_logic_vector(3 downto 0)
    );
end uart_trx;

architecture Behavioral of uart_trx is

begin
    --  RECEIVER
    UART_RX:    entity work.uRX(Behavioral)
        generic map (
            data_bit => data_bit,
            parity_bit => parity_bit,
            stop_bit => stop_bit,
            parity_typ => parity_typ,
            link_speed => link_speed
        )
        port map (
            sysClk => sysClk,
            sysRstb => sysRstb,
            serial_in => serial_input,
            rx_data => data_out,
            new_data => data_rx,
            data_ack => data_rx_ack,
            stage_dbg => rx_stage_dbg
        );
    
    --  TRANSMITTER
    UART_TX:    entity work.uTX(Behavioral)
        generic map (
            data_bit => data_bit,
            parity_bit => parity_bit,
            stop_bit => stop_bit,
            parity_typ => parity_typ,
            link_speed => link_speed
        )
        port map (
            sysClk => sysClk,
            sysRstb => sysRstb,
            serial_out => serial_output,
            tx_data => data_in,
            tx_start => data_tx,
            tx_done => data_tx_done
        );    
end Behavioral;
