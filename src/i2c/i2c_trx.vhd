library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

------------------------------------------------------------------------------------------------------------------
--
--  i2c bus transceiver
--  
--  an operation on the i2c bus is initiated when 'start_send' is pulled high. This signal must be kept high
--  until a high occurrs on 'done_send' or 'drdy' depending on the nature of the command (write or read).
--  if the transaction is comprised of multiple bytes to be written/read sequentially (the internal register of the
--  device is automatically updated by the device itself as in the case of EEPROMs for instance...), then it is
--  possible at this point to change the input to the device/get the read data and, after this, pull 'start_send' low.
--  once 'start_send' is low, it will latch the new data to the transceiver (if the command was a write) and it will acknowledge
--  this by pulling 'done_send' or 'drdy' back low. At this point 'start_send' must be set HIGH again and wait for the next
--  done_send / drdy high event, and so on. Once all the bytes have been written/read, it is sufficient to bring 'start_send' back
--  low to free the transceiver that will go into idle state.
--
--
entity i2c_trx is
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  i2c bus
        i2c_scl: out std_logic;
        i2c_sda: inout std_logic;
        --  interface
        bus_speed: in std_logic_vector(1 downto 0);     --  i2c bus speed
        bus_cmd: in std_logic;                          --  i2c bus command: 0 = write, 1 = read
        dev_addr: in std_logic_vector(6 downto 0);      --  i2c bus device address
        dev_reg_N: in std_logic_vector(7 downto 0);     --  how many bytes for the device's register
        dev_N_tr: in std_logic_vector(7 downto 0);      --  how many bytes to send in a single transaction
        --  control line
        start_send: in std_logic;                       --  starts and synchronizes the i2c driver operation
        --  data bus input
        data_input: in std_logic_vector(7 downto 0);    --  input data to send over the bus
        done_send: out std_logic;                       --  synchronization signal for a write operation completion
        --  data bus output
        data_output: out std_logic_vector(7 downto 0);  --  output data received from the bus
        drdy: out std_logic;                            --  synchronization signal for a read operation completion
        dev_error: out std_logic;                       --  in case the i2c device does not respond or a fault occurrs
        --  debug
        dbg: out natural
    );
end i2c_trx;

architecture Behavioral of i2c_trx is
    --  signal frequencies
    type SPD_ARRAY is array (0 to 3) of integer;
    --signal i2c_full_speeds: SPD_ARRAY := (500, 125, 50, 15);
    signal i2c_quad_speeds: SPD_ARRAY := (250, 63, 25, 8);
    --signal i2c_quad_speeds: SPD_ARRAY := (125, 32, 12, 4);
    --signal i2c_full_T: integer := i2c_full_speeds(to_integer(unsigned(bus_speed)));
    --signal i2c_half_T: integer := i2c_half_speeds(to_integer(unsigned(bus_speed)));
    signal i2c_quad_T: integer := i2c_quad_speeds(to_integer(unsigned(bus_speed)));
    
    --  sda and scl control buffers
    signal r_sda_dir: std_logic := '0';
    signal from_sda: std_logic := '0';
    signal to_sda: std_logic := '1';
    signal to_scl: std_logic := '1';
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_START_0, s_START_1, s_START_2, s_START_3, s_STOP_0, s_STOP_1, s_STOP_2, s_STOP_3, s_BIT_0, s_BIT_1, s_BIT_2, s_BIT_3,
    s_ADDR_0, s_ADDR_1, s_ADDR_2, s_REGCHECK_0, s_REGCHECK_1, s_REGCHECK_2, s_WRITE_0, s_WRITE_1, s_WRITE_2, s_WRITE_3, s_WRITE_4, s_WRITE_5,
    s_RBIT_0, s_RBIT_1, s_RBIT_2, s_RBIT_3, s_READ_0, s_READ_1, s_READ_2, s_READ_3, s_READ_4, s_READ_5, s_READ_6, s_READ_7, s_END_0, s_ENDERR_0);
    signal r_stage: t_SM := s_INIT;
    signal r_jump_L0: t_SM := s_INIT;
    signal r_jump_L1: t_SM := s_INIT;
    signal r_jump_L2: t_SM := s_INIT;
    
    --  helper registers
    signal r_bus_cmd: std_logic := '0';
    signal r_dev_addr: std_logic_vector(6 downto 0) := (others=>'0');
    signal r_dev_reg_N: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_dev_N_tr: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_data_input: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_data_output: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_drdy: std_logic := '0';
    signal r_error: std_logic := '0';
    signal r_start_send: std_logic := '0';
    signal r_done_send: std_logic := '0';
    
    signal r_bit_send: std_logic := '0';
    signal r_bit_sample: std_logic := '0';
    signal r_bit_cmd: std_logic := '0';
    signal r_word_send: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_word_read: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_N: std_logic_vector(7 downto 0) := (others=>'0');
    
begin
    --  buffer to drive the sda
    SDA_DRIVER: entity work.inout_port(Behavioral)
        generic map (
            nbits => 1
        )
        port map (
            io(0) => i2c_sda,
            data_to(0) => to_sda,
            data_from(0) => from_sda,
            dir => r_sda_dir        
        );

    --  sampler
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                r_bus_cmd <= '0';
                                r_dev_addr <= (others=>'0');
                                r_dev_reg_N <= (others=>'0');
                                r_dev_N_tr <= (others=>'0');
                                r_data_input <= (others=>'0');
                                r_start_send <= '0';
                            
                            when s_IDLE =>
                                r_bus_cmd <= bus_cmd;
                                r_dev_addr <= dev_addr;
                                r_dev_reg_N <= dev_reg_N;
                                r_dev_N_tr <= dev_N_tr;
                                r_data_input <= data_input;
                                r_start_send <= start_send;
                            
                            when s_WRITE_3 =>
                                r_start_send <= start_send;
                           
                            when s_WRITE_4 =>
                                r_data_input <= data_input;
                                r_start_send <= start_send;
                            
                            when s_WRITE_5 =>
                                r_start_send <= start_send;
                            
                            when s_READ_4 =>
                                r_start_send <= start_send;
                            
                            when s_READ_6 =>
                                r_start_send <= start_send;
                            
                            when s_READ_7 =>
                                r_start_send <= start_send;
                                                        
                            when s_END_0 =>
                                r_start_send <= start_send;
                            
                            when s_ENDERR_0 =>
                                r_start_send <= start_send;
                        
                            when others =>
                                null;
                                
                        end case;
                    end if;
                end process SAMPLER;
    
    --  main process and sampler
    MAIN:   process(sysClk)
                variable tC: integer := 0;
                variable bitIdx: integer := 0;
                variable RbitIdx: integer := 0;
                variable wC: integer := 0;
            begin
                if (rising_edge(sysClk)) then
                    if (sysRstb='0') then
                        r_stage <= s_INIT;
                    else
                        case (r_stage) is
                            when s_INIT =>
                                r_sda_dir <= '1';
                                to_sda <= '1';
                                to_scl <= '1';
                                r_done_send <= '0';
                                r_word_read <= (others=>'0');
                                r_drdy <= '0';
                                r_bit_send <= '0';
                                r_bit_sample <= '0';
                                r_bit_cmd <= '0';
                                r_word_send <= (others=>'0');
                                r_N <= (others=>'0');
                                tC := 0;
                                bitIdx := 0;
                                RbitIdx := 0;
                                wC := 0;
                                r_stage <= s_IDLE;
                            
                            when s_IDLE =>
                                dbg <= 0;
                                --  waiting for a command to occurr
                                if (r_start_send='1') then
                                    --  need to start transmitting
                                    if (r_bus_cmd='0') then
                                        dbg <= 1;
                                    else
                                        dbg <= 240;
                                    end if;
                                    r_bit_cmd <= '0';
                                    r_jump_L1 <= s_REGCHECK_0;
                                    r_stage <= s_ADDR_0;
                                else
                                    --  waiting here
                                    r_stage <= s_IDLE;
                                end if;
                        
                            ----------------------------------------------------------------------------------------------------
                            --  START CONDITION
                            ----------------------------------------------------------------------------------------------------
                            --
                            when s_START_0 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition
                                    to_sda <= '1';
                                    to_scl <= '0';
                                    tC := 0;
                                    r_stage <= s_START_1;
                                else
                                    --  need to wait
                                    to_sda <= to_sda;
                                    to_scl <= '0';
                                    tC := tC + 1;
                                    r_stage <= s_START_0;
                                end if;
                            
                            when s_START_1 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition
                                    to_scl <= '1';
                                    to_sda <= '1';
                                    tC := 0;
                                    r_stage <= s_START_2;
                                else
                                    --  need to wait
                                    to_scl <= '0';
                                    to_sda <= '1';
                                    tC := tC + 1;
                                    r_stage <= s_START_1;
                                end if;
                            
                            when s_START_2 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition
                                    to_scl <= '1';
                                    to_sda <= '0';
                                    tC := 0;
                                    r_stage <= s_START_3;
                                else
                                    --  need to wait
                                    to_scl <= '1';
                                    to_sda <= '1';
                                    tC := tC + 1;
                                    r_stage <= s_START_2;
                                end if;
                            
                            when s_START_3 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition
                                    to_scl <= '0';
                                    to_sda <= '0';
                                    tC := 0;
                                    r_stage <= r_jump_L0;
                                else
                                    --  need to wait
                                    to_scl <= '1';
                                    to_sda <= '0';
                                    tC := tC + 1;
                                    r_stage <= s_START_3;
                                end if;
                            --
                            ----------------------------------------------------------------------------------------------------
                            --  STOP CONDITION
                            ----------------------------------------------------------------------------------------------------
                            --
                            when s_STOP_0 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition
                                    to_scl <= '0';
                                    to_sda <= '0';
                                    tC := 0;
                                    r_stage <= s_STOP_1;
                                else
                                    --  need to wait
                                    to_scl <= '0';
                                    to_sda <= to_sda;
                                    tC := tC + 1;
                                    r_stage <= s_STOP_0;
                                end if;
                        
                            when s_STOP_1 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition
                                    to_scl <= '1';
                                    to_sda <= '0';
                                    tC := 0;
                                    r_stage <= s_STOP_2;
                                else
                                    --  need to wait
                                    to_scl <= '0';
                                    to_sda <= '0';
                                    tC := tC + 1;
                                    r_stage <= s_STOP_1;
                                end if;
                        
                            when s_STOP_2 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition
                                    to_scl <= '1';
                                    to_sda <= '1';
                                    tC := 0;
                                    r_stage <= s_STOP_3;
                                else
                                    --  need to wait
                                    to_scl <= '1';
                                    to_sda <= '0';
                                    tC := tC + 1;
                                    r_stage <= s_STOP_2;
                                end if;
                        
                            when s_STOP_3 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  done
                                    tC := 0;
                                    r_stage <= r_jump_L2;
                                else
                                    --  need to wait
                                    to_scl <= '1';
                                    to_sda <= '1';
                                    tC := tC + 1;
                                    r_stage <= s_STOP_3;
                                end if;
                            --
                            ----------------------------------------------------------------------------------------------------
                            --  BIT TRANSMIT
                            ----------------------------------------------------------------------------------------------------
                            --
                            when s_BIT_0 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition for sda
                                    to_sda <= r_bit_send;
                                    to_scl <= '0';
                                    tC := 0;
                                    r_stage <= s_BIT_1;
                                else
                                    --  waiting
                                    to_scl <= '0';
                                    to_sda <= to_sda;
                                    tC := tC + 1;
                                    r_stage <= s_BIT_0;
                                end if;
                        
                            when s_BIT_1 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition for scl
                                    to_scl <= '1';
                                    to_sda <= to_sda;
                                    tC := 0;
                                    r_stage <= s_BIT_2;
                                else
                                    --  waiting
                                    to_scl <= '0';
                                    to_sda <= to_sda;
                                    tC := tC + 1;
                                    r_stage <= s_BIT_1;
                                end if;
                        
                            when s_BIT_2 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  going
                                    to_scl <= to_scl;
                                    to_sda <= to_sda;
                                    tC := 0;
                                    r_stage <= s_BIT_3;
                                else
                                    --  waiting
                                    to_scl <= to_scl;
                                    to_sda <= to_sda;
                                    tC := tC + 1;
                                    r_stage <= s_BIT_2;
                                end if;
                        
                            when s_BIT_3 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transition
                                    to_scl <= '0';
                                    to_sda <= to_sda;
                                    tC := 0;
                                    r_stage <= r_jump_L0;
                                else
                                    --  waiting
                                    to_scl <= to_scl;
                                    to_sda <= to_sda;
                                    tC := tC + 1;
                                    r_stage <= s_BIT_3;
                                end if;
                            ----------------------------------------------------------------------------------------------------
                            --  ACK/NACK bit
                            ----------------------------------------------------------------------------------------------------
                            when s_RBIT_0 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  relinquishing the bus
                                    r_sda_dir <= '0';
                                    tC := 0;
                                    r_stage <= s_RBIT_1;
                                else
                                    --  waiting
                                    r_sda_dir <= '1';
                                    to_scl <= '0';
                                    to_sda <= '0';
                                    tC := tC + 1;
                                    r_stage <= s_RBIT_0;
                                end if;
                            
                            when s_RBIT_1 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transitioning
                                    to_scl <= '1';
                                    tC := 0;
                                    r_stage <= s_RBIT_2;
                                else
                                    --  waiting
                                    r_sda_dir <= '0';
                                    to_scl <= '0';
                                    tC := tC + 1;
                                    r_stage <= s_RBIT_1;
                                end if;
                            
                            when s_RBIT_2 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  sampling in the middle
                                    r_bit_sample <= from_sda;
                                    tC := 0;
                                    r_stage <= s_RBIT_3;
                                else
                                    --  waiting
                                    r_sda_dir <= '0';
                                    to_scl <= '1';
                                    tC := tC + 1;
                                    r_stage <= s_RBIT_2;
                                end if;
                            
                            when s_RBIT_3 =>
                                if (tC=(i2c_quad_T-1)) then
                                    --  transitioning and getting back the bus
                                    to_scl <= '0';
                                    r_sda_dir <= '1';
                                    tC := 0;
                                    r_stage <= r_jump_L0;
                                else
                                    --  waiting
                                    r_sda_dir <= '0';
                                    to_scl <= '1';
                                    tC := tC + 1;
                                    r_stage <= s_RBIT_3;
                                end if;
                            ----------------------------------------------------------------------------------------------------
                            --  SENDING ADDRESS
                            ----------------------------------------------------------------------------------------------------
                            when s_ADDR_0 =>
                                dbg <= 1;
                                --  first thing to do is to send the start condition
                                bitIdx := 0;
                                r_stage <= s_START_0;
                                r_jump_L0 <= s_ADDR_1;
                            
                            when s_ADDR_1 =>
                                dbg <= 2;
                                --  now we must send the address bits, so
                                r_bit_send <= r_dev_addr(6-bitIdx);
                                r_stage <= s_BIT_0;
                                r_jump_L0 <= s_ADDR_2;
                            
                            when s_ADDR_2 =>
                                dbg <= 3;
                                --  the bit has been sent
                                if (bitIdx=7) then
                                    --  all is done with the address bits + write command, need now to acknowledge
                                    r_stage <= s_RBIT_0;
                                    r_jump_L0 <= r_jump_L1;
                                else
                                    if (bitIdx=6) then
                                        r_bit_send <= r_bit_cmd;
                                        bitIdx := 7;
                                        r_stage <= s_BIT_0;
                                    else
                                        bitIdx := bitIdx + 1;
                                        r_stage <= s_ADDR_1;
                                    end if;
                                end if;
                            --
                            ----------------------------------------------------------------------------------------------------
                            --  CHECKING WHAT TO DO -> devo mettere l'acknowledge!
                            ----------------------------------------------------------------------------------------------------
                            --
                            when s_REGCHECK_0 =>
                                dbg <= 4;
                                --  checking firstly the ACK/NACK
                                if (r_bit_sample='0') then
                                    --  we have an ACK
                                    if (to_integer(unsigned(r_dev_reg_N))=0) then
                                        --  no register address is needed -> can proceed with the data operation
                                        r_stage <= s_REGCHECK_2;
                                    else
                                        --  need to send N words to specify the device register onto which we have to act
                                        bitIdx := 0;
                                        wC := 0;
                                        r_word_send <= r_data_input;
                                        r_N <= r_dev_reg_N;
                                        r_stage <= s_WRITE_0;
                                        r_jump_L1 <= s_REGCHECK_1;
                                    end if;
                                else
                                    --  we have a NACK -> must terminate
                                    r_stage <= s_STOP_0;
                                    r_jump_L2 <= s_ENDERR_0;
                                end if;
                            
                            when s_REGCHECK_1 =>
                                dbg <= 5;
                                --  the byte(s) for the register's address have been written, now it's the time for the data byte(s)
                                if (r_bus_cmd='0') then
                                    --  prepare to get the first byte
                                    bitIdx := 0;
                                    wC := 0;
                                    r_N <= r_dev_N_tr;
                                    r_stage <= s_WRITE_4;
                                    r_jump_L1 <= s_STOP_0;
                                    r_jump_L2 <= s_END_0;
                                else
                                    --  read
                                    RbitIdx := 0;
                                    wC := 0;
                                    r_N <= r_dev_N_tr;
                                    r_stage <= s_READ_7;
                                end if;
 
                            when s_REGCHECK_2 =>
                                dbg <= 6;
                                --  it is time to check the command type
                                if (r_bus_cmd='0') then
                                    bitIdx := 0;
                                    wC := 0;
                                    r_word_send <= r_data_input;
                                    r_N <= r_dev_N_tr;
                                    r_stage <= s_WRITE_0;
                                    r_jump_L1 <= s_STOP_0;
                                    r_jump_L2 <= s_END_0;
                                else
                                    --  read
                                    RbitIdx := 0;
                                    wC := 0;
                                    r_N <= r_dev_N_tr;
                                    r_stage <= s_READ_0;
                                end if;
                            
                            --
                            ----------------------------------------------------------------------------------------------------
                            --  SENDING DATA OVER (wC counter)
                            ----------------------------------------------------------------------------------------------------
                            --
                            when s_WRITE_0 =>
                                dbg <= 7;
                                --  initializing the counters
                                r_bit_send <= r_word_send(7-bitIdx);
                                r_stage <= s_BIT_0;
                                r_jump_L0 <= s_WRITE_1;
                        
                            when s_WRITE_1 =>
                                dbg <= 8;
                                --  checking
                                if (bitIdx=7) then
                                    --  sent all the bits for this word -> reading the ack bit
                                    r_stage <= s_RBIT_0;
                                    r_jump_L0 <= s_WRITE_2;
                                else
                                    --  still have more bits to send over of this same word
                                    bitIdx := bitIdx + 1;
                                    r_stage <= s_WRITE_0;
                                end if;
                            
                            when s_WRITE_2 =>
                                dbg <= 9;
                                if (r_bit_sample='0') then
                                    --  signalling end of writing for this byte
                                    if (wC=(to_integer(unsigned(r_N))-1)) then
                                        --  done with writing, so
                                        r_done_send <= '1';
                                        r_stage <= s_WRITE_5;
                                    else
                                        --  still have more data to send in the same transaction
                                        r_stage <= s_WRITE_3;
                                    end if;
                                else
                                    --  received a NACK for some reason (dev fault?) => must terminate
                                    r_stage <= s_STOP_0;
                                    r_jump_L2 <= s_ENDERR_0;
                                end if;
                        
                            when s_WRITE_3 =>
                                dbg <= 10;
                                if (r_start_send='0') then
                                    --  once this go low, we have new data latched and ready to go, so
                                    bitIdx := 0;
                                    wC := wC + 1;
                                    r_stage <= s_WRITE_4;
                                else
                                    --  waiting for r_start_send to go low
                                    r_drdy <= '1';
                                    r_stage <= s_WRITE_3;
                                end if;
                            
                            when s_WRITE_4 =>
                                dbg <= 11;
                                if (r_start_send='1') then
                                    r_word_send <= r_data_input;
                                    r_stage <= s_WRITE_0;
                                else
                                    r_drdy <= '0';
                                    r_stage <= s_WRITE_4;
                                end if;
                            
                            when s_WRITE_5 =>
                                dbg <= 12;
                                if (r_start_send='0') then
                                    r_done_send <= '0';
                                    r_stage <= r_jump_L1;
                                else     
                                    r_drdy <= '1';                               
                                    r_stage <= s_WRITE_5;
                                end if;
                                
                            --
                            ----------------------------------------------------------------------------------------------------
                            --  READING DATA FROM
                            ----------------------------------------------------------------------------------------------------
                            --  
                            when s_READ_0 =>
                                dbg <= 13;
                                --  sending the repeated start condition with the address and command 1
                                RbitIdx := 0;
                                r_bit_cmd <= '1';
                                r_stage <= s_ADDR_0;
                                r_jump_L1 <= s_READ_1;
                            
                            when s_READ_1 =>
                                dbg <= 14;
                                --  now we have to release the SDA and drive the SCL in order to fetch the 8 bits
                                r_stage <= s_RBIT_0;
                                r_jump_L0 <= s_READ_2;
                            
                            when s_READ_2 =>
                                dbg <= 15;
                                --  we have just read a bit from the device, so
                                r_word_read(7-RbitIdx) <= r_bit_sample;
                                r_stage <= s_READ_3;
                            
                            when s_READ_3 =>
                                dbg <= 16;
                                if (RbitIdx=7) then
                                    --  we have read a byte -> must send it out and see if it has to read more
                                    if (wC=(to_integer(unsigned(r_N))-1)) then
                                        r_done_send <= '1';
                                    else
                                        r_done_send <= '0';
                                    end if;
                                    r_stage <= s_READ_4;
                                else
                                    --  still has to read bits for this byte
                                    RbitIdx := RbitIdx + 1;
                                    r_stage <= s_RBIT_0;
                                end if;
                                                        
                            when s_READ_4 =>
                                dbg <= 17;
                                --  waiting for r_start_send to go to 1
                                if (r_start_send='0') then
                                    --  the byte has been acknowledged
                                    r_drdy <= '0';
                                    r_done_send <= '0';
                                    r_stage <= s_READ_5;
                                else
                                    --  the read byte hasn't been acknowledged yet
                                    r_drdy <= '1';                                    
                                    r_stage <= s_READ_4;
                                end if;
                                                                                                               
                            when s_READ_5 =>
                                dbg <= 18;
                                if (wC=(to_integer(unsigned(r_N))-1)) then
                                    --  no more bytes to read from the device, so we must send a NACK to terminate the transaction
                                    r_bit_send <= '1';
                                    r_stage <= s_BIT_0;
                                    r_jump_L0 <= s_STOP_0;
                                    r_jump_L2 <= s_END_0;
                                else
                                    --  need to read more sequentially, so
                                    RbitIdx := 0;
                                    wC := wC + 1;
                                    --  we have to first send an ACK to proceed
                                    r_bit_send <= '0';
                                    r_stage <= s_READ_6;
                                    r_jump_L0 <= s_READ_1;
                                end if;
                            
                            when s_READ_6 =>
                                dbg <= 19;
                                if (r_start_send='1') then
                                    r_stage <= s_BIT_0;
                                else
                                    r_stage <= s_READ_6;
                                end if;
                            
                            when s_READ_7 =>
                                dbg <= 20;
                                if (r_start_send='1') then
                                    r_stage <= s_READ_0;
                                else
                                    r_drdy <= '0';
                                    r_stage <= s_READ_7;
                                end if;                                         
                            --
                            ----------------------------------------------------------------------------------------------------
                            --  END CONDITIONS: EDITED TO AVOID LOCKS
                            ----------------------------------------------------------------------------------------------------
                            -- 
                            when s_END_0 =>
                                dbg <= 21;
                                r_error <= '0';
                                r_done_send <= '0';
                                r_drdy <= '0';
                                r_stage <= s_IDLE;
                            
                            when s_ENDERR_0 =>
                                dbg <= 22;
                                if (r_start_send='0') then
                                    --  ok
                                    r_stage <= s_END_0;
                                else
                                    --  showing the error condition
                                    r_error <= '1';
                                    r_stage <= s_ENDERR_0;
                                end if;
                                                    
                        end case;
                    end if;
                end if;
            end process MAIN;

    --  assignments
    i2c_scl <= to_scl;
    done_send <= r_done_send;
    data_output <= r_word_read;
    drdy <= r_drdy;
    dev_error <= r_error;

end Behavioral;
