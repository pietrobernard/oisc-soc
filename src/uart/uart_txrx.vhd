library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_txrx is
    generic (
        --  uart options
        parity_bit: integer range 0 to 1 := 0;  -- 0: no parity bit, 1: parity enabled
        parity_typ: integer range 0 to 3 := 0   -- 0: even parity, 1: odd parity, 2: mark parity, 3: space parity
    );
    port (
        --  systemwide signals
        sysClk:     in  std_logic;
        sysRstb:    in  std_logic;
        --  output data from the RX
        data_from:  out std_logic_vector(7 downto 0);
        data_rdy:   out std_logic;
        data_get:   in  std_logic;
        --  input data to the TX
        data_to:    in  std_logic_vector(7 downto 0);
        data_send:  in  std_logic;
        data_ok:    out std_logic := '0';
        --  hardware lines
        serial_in:  in  std_logic;
        serial_out: out std_logic;
        --  status lines
        parity_err: out std_logic
    );
end uart_txrx;

architecture Behavioral of uart_txrx is
    signal  syncOK: std_logic := '0';
    signal  uart_bit_period:    std_logic_vector(15 downto 0) := (others => '0');
    signal  uart_bit_halfperiod:    std_logic_vector(15 downto 0) := (others => '0');
begin
    --  RX entity that will listen for events on the 'serial_in' line
    RX: entity work.uart_RX(Behavioral)
        generic map (
            parity_bit => parity_bit,
            parity_typ => parity_typ
        )
        port map (
            sysClk => sysClk,
            sysRstb => sysRstb,
            data_from => data_from,
            data_rdy => data_rdy,
            data_get => data_get,
            serial_in => serial_in,
            par_error => parity_err,
            enable => syncOK,
            uart_period => uart_bit_period,
            uart_hperiod => uart_bit_halfperiod
        );

    --  TX entity that will drive the 'serial_out' line
    TX: entity work.uart_TX(Behavioral)
        generic map (
            parity_bit => parity_bit,
            parity_typ => parity_typ
        )
        port map (
            sysClk => sysClk,
            sysRstb => sysRstb,
            data_to => data_to,
            data_send => data_send,
            data_ok => data_ok,
            serial_out => serial_out,
            enable => syncOK,
            uart_period => uart_bit_period,
            uart_hperiod => uart_bit_halfperiod
        );

    --  SYNC entity that will get the link speed before enabling the RX and TX modules
    SYNC: entity work.uart_SYNC(Behavioral)
          port map (
            sysClk => sysClk,
            sysRstb => sysRstb,
            O_fullperiod => uart_bit_period,
            O_halfperiod => uart_bit_halfperiod,
            syncOK => syncOK,
            serial_in => serial_in
          );
end Behavioral;
