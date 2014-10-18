-- BrainF* interpreter - testbench
-- Version: 20141001
-- Author:  Ronald Landheer-Cieslak
-- Copyright (c) 2014  Vlinder Software
-- License: http://opensource.org/licenses/CDDL-1.0
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.txt_util.all;

entity BrainF_tb is
end entity;
architecture behavior of BrainF_tb is
    constant WARMUP_COUNTDOWN : integer := 4;
    constant INITIAL_COUNTDOWN : integer := 10;
    --constant PROGRAM : string := "++++++++";
    --constant PROGRAM : string := "[.]";
    --constant PROGRAM : string := "-+[-+][[-+]]";
    --constant PROGRAM : string := "++[-][[-+]]";
    --constant PROGRAM : string := ">+++++++++[<++++++++>-]<.>+++++++[<++++>-]<+.+++++++..+++.0>++++++++[<++++>-] <.>+++++++++++[<++++++++>-]<-.--------.+++.------.--------.0>++++++++[<++++>- ]<+.0++++++++++.";
    constant PROGRAM : string := ">+++++++++[<++++++++>-]<.>+++++++[<++++>-]<+.+++++++..+++.[-]>++++++++[<++++>-] <.>+++++++++++[<++++++++>-]<-.--------.+++.------.--------.[-]>++++++++[<++++>- ]<+.[-]++++++++++.";
    constant PROGRAM_TIMEOUT : Time := 138 ns;

    component BrainF is
        generic(
              MAX_INSTRUCTION_COUNT : positive := 65536
            ; MEMORY_SIZE : positive := 65536
            );
        port(
              resetN : in std_logic
            ; clock : in std_logic
            
            ; load_instructions : in std_logic
            ; instruction_octet : in std_logic_vector(7 downto 0)
            ; ack_instruction : out std_logic
            ; program_full : out std_logic
            
            ; read_memory : in std_logic
            ; memory_byte : out std_logic_vector(7 downto 0)
            ; memory_byte_ready : out std_logic
            ; memory_byte_read_ack : in std_logic
            
            ; done : out std_logic
            );
    end component;
    type State is (warmup, initial, start_loading_program, loading_program, running_program, success);
    
    function to_std_logic_vector(c : character) return std_logic_vector is
        variable cc : integer;
    begin
        cc := character'pos(c);
        return std_logic_vector(to_unsigned(cc, 8));
    end to_std_logic_vector;
    
    signal clock                    : std_logic := '0';
    
    signal load_instructions        : std_logic := '0';
    signal instruction_octet        : std_logic_vector(7 downto 0) := (others => '0');
    signal ack_instruction          : std_logic := '0';
    signal program_full             : std_logic := '0';
    signal read_memory              : std_logic := '0';
    signal memory_byte              : std_logic_vector(7 downto 0) := (others => '0');
    signal memory_byte_ready        : std_logic := '0';
    signal memory_byte_read_ack     : std_logic := '0';
    signal done                     : std_logic := '0';
    
    signal tb_state                 : State := warmup;  
    
    signal should_be_done           : std_logic := '0';
    
    signal end_of_simulation        : std_logic := '0';
begin
    interpreter : BrainF
        port map(
              resetN => '1'
            , clock => clock
            , load_instructions => load_instructions
            , instruction_octet => instruction_octet
            , ack_instruction => ack_instruction
            , program_full => program_full
            , read_memory => read_memory
            , memory_byte => memory_byte
            , memory_byte_ready => memory_byte_ready
            , memory_byte_read_ack => memory_byte_read_ack
            , done => done
            );
    -- generate the clock
    clock <= not clock after 1 ps;
    -- generate the time-out signal
    should_be_done <= '1' after PROGRAM_TIMEOUT;
    
    p_tb : process(clock)
        variable countdown : integer := WARMUP_COUNTDOWN;
        variable program_load_counter : integer := 0;
    begin
        if rising_edge(clock) then
            case tb_state is
            when warmup =>
                assert done = '0' report "Cannot be done while warming up (pipe filling with halt instructions)" severity failure;
                assert program_full = '0' report "Program cannot be initially full" severity failure;
                assert ack_instruction = '0' report "Cannot acknowledge an instruction I haven't given yet" severity failure;
                assert memory_byte_ready = '0' report "Cannot have memory ready when I haven't asked for anything yet" severity failure;
                if countdown = 1 then
                    tb_state <= initial;
                    countdown := INITIAL_COUNTDOWN;
                else
                    countdown := countdown - 1;
                end if;
            when initial =>
                assert done = '1' report "Once warmed up, it should know it has no program and say it's done" severity failure;
                assert program_full = '0' report "Program cannot be initially full" severity failure;
                assert ack_instruction = '0' report "Cannot acknowledge an instruction I haven't given yet" severity failure;
                assert memory_byte_ready = '0' report "Cannot have memory ready when I haven't asked for anything yet" severity failure;
                if countdown = 1 then
                    tb_state <= start_loading_program;
                else
                    countdown := countdown - 1;
                end if;
            when start_loading_program =>
                assert program_full = '0' report "Program cannot be initially full" severity failure;
                assert ack_instruction = '0' report "Cannot acknowledge an instruction I haven't given yet" severity failure;
                assert memory_byte_ready = '0' report "Cannot have memory ready when I haven't asked for anything yet" severity failure;
                instruction_octet <= to_std_logic_vector(program(1));
                load_instructions <= '1';
                tb_state <= loading_program;
                program_load_counter := 2;
            when loading_program =>
                if program_load_counter <= program'length then
                    if ack_instruction = '1' then
                        instruction_octet <= to_std_logic_vector(program(program_load_counter));
                        program_load_counter := program_load_counter + 1;
                    end if;
                else
                    load_instructions <= '0';
                    tb_state <= running_program;
                end if;
            when running_program =>
                if should_be_done = '1' then
                    assert done = '1' report "Timeout!" severity failure;
                end if;
                if done = '1' then 
                    tb_state <= success;
                end if;
            when success =>
                end_of_simulation <= '1';
            when others => null;
            end case;
        end if;
    end process;    
end behavior;
