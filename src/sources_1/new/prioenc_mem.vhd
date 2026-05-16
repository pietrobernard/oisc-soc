library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

entity prioenc_mem is
    generic (
        n_entries_bits: natural := 7;
        n_idx_bits: natural := 3;
        n_entries: natural := 128;
        n_bits: natural := 4;
        cfgfile: string := "priority_encoder_7bit.mem"
    );
    port (
        snapshot: in std_logic_vector(n_entries_bits-1 downto 0);
        prioidx: out std_logic_vector(n_idx_bits-1 downto 0);
        act: out std_logic
    );
end prioenc_mem;

architecture Behavioral of prioenc_mem is
    --  function to load up the register setup
    type cfgram_type is array (0 to n_entries) of std_logic_vector(n_bits-1 downto 0);
    impure function init_ram_bin return cfgram_type is 
      file text_file : text open read_mode is cfgfile;
      variable text_line : line;
      variable ram_content : cfgram_type;
      variable bv : bit_vector(ram_content(0)'range);
    begin
      for i in 0 to n_entries - 1 loop
        readline(text_file, text_line);
        read(text_line, bv);
        ram_content(i) := to_stdlogicvector(bv);
      end loop;
      return ram_content;
    end function;
    
    --  loading up the register configuration
    signal priority_encoder: cfgram_type := init_ram_bin;
    
    signal prio_line: std_logic_vector(n_bits-1 downto 0);
begin
    prio_line <= priority_encoder(to_integer(unsigned(snapshot)));
    prioidx <= prio_line(n_bits-1 downto 1);
    act <= prio_line(0);
end Behavioral;
