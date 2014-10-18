-- BrainF* interpreter  
-- Version: 20141018
-- Author:  Ronald Landheer-Cieslak
-- Copyright (c) 2014  Vlinder Software
-- License: LGPL-3.0
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity BrainF_top is
    port(
          resetN : in std_logic
        ; clock : in std_logic
        );
end entity;
architecture behavior of BrainF_top is
    component BrainF is
        generic(
              MAX_INSTRUCTION_COUNT : positive
            ; MEMORY_SIZE : positive
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

    signal load_instructions : std_logic := '0';
    signal instruction_octet : std_logic_vector(7 downto 0) := (others => '0');
begin
    interpreter : BrainF
        generic map(
              MAX_INSTRUCTION_COUNT => 65535
            , MEMORY_SIZE => 65535
            )
        port map(
              resetN => resetN
            , clock => clock
            
            , load_instructions => load_instructions
            , instruction_octet => instruction_octet
            , ack_instruction => open
            , program_full => open
            
            , read_memory => '0'
            , memory_byte => open
            , memory_byte_ready => open
            , memory_byte_read_ack => '0'
            
            , done => open
            );
end behavior;
