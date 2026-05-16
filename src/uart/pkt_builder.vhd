library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pkt_builder is
    generic (
        data_bit:       integer := 8;
        parity_bit:     integer range 0 to 1 := 0;  --  number of parity bits: 0 or 1
        stop_bit:       integer range 0 to 1 := 0   --  number of stop bits: 1 or 2
    );
    port (
        data_in: in std_logic_vector(7 downto 0);
        parity: in std_logic;
        data_out: out std_logic_vector(11 downto 0)
    );
end pkt_builder;

architecture Behavioral of pkt_builder is
    constant packet_size: integer := 1 + data_bit + parity_bit + stop_bit + 1;
    --  so, no parity and 1 stop -> 10 bit wide packet
begin
    data_out(0) <= '0';                         --  start bit
    data_out(data_bit downto 1) <= data_in;     --  data bits
    data_out(data_bit + 1) <= (parity or '1');  --  parity or stop bit
    data_out((data_bit+3) downto (data_bit+2)) <= "11";
end Behavioral;
