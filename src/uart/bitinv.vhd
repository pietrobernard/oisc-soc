library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bitinv is
    port (
        inputData:  in std_logic_vector(7 downto 0);
        outputData: out std_logic_vector(7 downto 0)
    );
end bitinv;

architecture Behavioral of bitinv is

begin
    --  inverto i bit
    outputData(0) <= inputData(7);
    outputData(1) <= inputData(6);
    outputData(2) <= inputData(5);
    outputData(3) <= inputData(4);
    outputData(4) <= inputData(3);
    outputData(5) <= inputData(2);
    outputData(6) <= inputData(1);
    outputData(7) <= inputData(0);
end Behavioral;
