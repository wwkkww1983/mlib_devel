%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                                             %
%   Center for Astronomy Signal Processing and Electronics Research           %
%   http://seti.ssl.berkeley.edu/casper/                                      %
%   Copyright (C) 2006 University of California, Berkeley                     %
%                                                                             %
%   This program is free software; you can redistribute it and/or modify      %
%   it under the terms of the GNU General Public License as published by      %
%   the Free Software Foundation; either version 2 of the License, or         %
%   (at your option) any later version.                                       %
%                                                                             %
%   This program is distributed in the hope that it will be useful,           %
%   but WITHOUT ANY WARRANTY; without even the implied warranty of            %
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             %
%   GNU General Public License for more details.                              %
%                                                                             %
%   You should have received a copy of the GNU General Public License along   %
%   with this program; if not, write to the Free Software Foundation, Inc.,   %
%   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.               %
%                                                                             %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [] = gen_block_file(compile_dir,output_fname,sys)
% Output the parameters of all xps-tagged blocks to the text file "peripherals.txt"
% so that they can be parsed by the reset of the toolflow

%if no system name is supplied, use gcs
if nargin > 2
    % load model file
    disp(sprintf('Loading model: %s',sys));
    load_system(sys);
end

this_sys = gcs;

% get system generator version. There are some small differences in the
% netlists generated depending on version

xlver = str2num(xilinx.environment.getversion('sysgen'));


% search for blocks in the system
xps_blks        = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all','RegExp','on',      'Tag', '^xps:')
xps_xsg_blks    = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all',                    'Tag', 'xps:xsg')
xps_pcore_blks  = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all',                    'Tag', 'xps:pcore')
sysgen_blk      = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all','SearchDepth', 1,   'Tag', 'genX');
casper_blks     = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all','RegExp','on',      'Tag', '^casper:');
gateway_ins     = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all',     'MaskType', 'Xilinx Gateway In Block')
gateway_outs    = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all',     'MaskType', 'Xilinx Gateway Out Block')
disregards      = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all',                    'Tag', 'discardX');

% parents of disregard blocks -- i.e., blocks we should ignore
dummy_parents = {};
for ctr = 1 : numel(disregards),
    dummy_parents{ctr} = get_param(disregards{ctr},'Parent')
end


% check for spaces in xps or casper block names
for ctr = 1 : numel(xps_blks),
    if numel(strfind(xps_blks{ctr}, ' ')) > 0,
        error('Block names may not have spaces - %s', xps_blks{ctr});
    end 
end
for ctr = 1 : numel(casper_blks),
    if numel(strfind(casper_blks{ctr}, ' ')) > 0,
        error('Block names may not have spaces - %s', casper_blks{ctr});
    end 
end


if length(xps_xsg_blks) ~= 1,
    error('There has to be exactly 1 XPS_XSG block on each chip level (sub)system (Is the current system the correct one ?)');
end

if length(sysgen_blk) == 1,
    xsg_blk = sysgen_blk{1};
else
    error('XPS_xsg block must be on the same level as the Xilinx SysGen block. Have you put a XSG block in you design, and is the current system the correct one?');
end

% comb for gateway in blocks that aren't part of a yellow block
gateways_blk = find_system(this_sys, 'FollowLinks', 'on', 'LookUnderMasks', 'all', 'masktype', 'Xilinx Gateway In Block');
for i = 1:length(gateways_blk),
    found_xps_tag = 0;
    parent = get_param(gateways_blk(i), 'parent');
    gw_parent = parent;

    while ~strcmp(parent, '')
        parent_tag = char(get_param(parent, 'tag'));
        if ~isempty(regexp(parent_tag, '^xps:', 'ONCE')),
            found_xps_tag = 1;
        end
        parent = get_param(parent,'parent');
    end

    if found_xps_tag == 0,
        disregard_blocks = find_system(gw_parent, 'FollowLinks', 'on', 'LookUnderMasks', 'all', 'masktype', 'Xilinx Disregard Subsystem For Generation');
        if isempty(disregard_blocks),
            error('Xilinx input gateways cannot be used in a design. Only XPS GPIO blocks should be used.');
        end
    end
end

simulink_path   = pwd;
% check paths
if ~isempty(strfind(simulink_path, ' ')),
    warndlg(['Working directory ', simulink_path, ' has a space in the pathname. This can cause problems with some of the tools. Please change your working directory.']);
    error('Working directory has a space in the pathname.');
end

% open a file to write block parameters to
disp(sprintf('Opening output file: %s',output_fname));
fid = fopen(output_fname,'w');

fprintf(fid,'yellow_blocks:\n');
for n = 1:length(xps_blks)
    % Save all the user specified parameters ('DialogParameters')
    % as well as the tag name, which identifies the block to the rest
    % of the toolflow
    block_params = get_param(xps_blks{n},'DialogParameters');
    fields = fieldnames(block_params);
    fprintf(fid,'  %s:\n',xps_blks{n});
    fprintf(fid,'    %s: %s\n','name',get_param(xps_blks{n},'Name'));
    fprintf(fid,'    %s: %s\n','fullpath', xps_blks{n});
    fprintf(fid,'    %s: %s\n','tag',get_param(xps_blks{n},'Tag'));
    for m = 1:length(fields)
        val = eval_param(xps_blks{n},fields{m});
        try
            val = num2str(val);
        end
        fprintf(fid,'    %s: %s\n',fields{m},yaml_sanitize(val));
    end
end 

% Write the names of all ports
% Maybe in future also include data types, but these are not trivially available
% from the gateway out block parameters, which inherit type.

fprintf(fid,'\nuser_modules:\n');
fprintf(fid,'  %s:\n',bdroot);
% explicitly add clock and clock enable ports, and give their names so that
% the rest of the toolflow handles them properly.
if xlver > 14.7
    fprintf(fid,'    clock: clk\n');
else
    fprintf(fid,'    clock: clk_1\n');
    fprintf(fid,'    clock_enable: ce_1\n');
end
fprintf(fid,'    ports:\n');
    
for n = 1:length(gateway_ins)
    if ~any(strcmp(dummy_parents, get_param(gateway_ins{n},'Parent')))
        get_param(gateway_ins{n},'Name');
        fprintf(fid,'      - %s\n',get_param(gateway_ins{n},'Name'));
    end
end 
for n = 1:length(gateway_outs)
    if ~any(strcmp(dummy_parents, get_param(gateway_outs{n},'Parent')))
        fprintf(fid,'      - %s\n',get_param(gateway_outs{n},'Name'));
    end
end 

% Write the paths of any custom IP that needs to be added to the project before the final compile.
% Expand relative paths for easy location of the files later.
% Vivado puts the compiled vhd netlist in a different place than earlier
% sysgen versions, so accommodate for that here.
xlver = str2num(xilinx.environment.getversion('sysgen'));
if xlver > 14.7
    path_to_netlist = [compile_dir '/sysgen/hdl_netlist/' bdroot '.srcs/sources_1/imports/sysgen'];
else
    path_to_netlist = [compile_dir '/sysgen/' bdroot '.vhd'];
end

    
fprintf(fid,'    sources:\n');    
fprintf(fid,'      - %s\n', path_to_netlist);
for n = 1:length(xps_pcore_blks)
    fprintf(fid,'      - %s\n',GetFullPath(get_param(xps_pcore_blks{n},'pcore_path')));
end 


disp(sprintf('Closing output file: %s',output_fname));
fclose(fid);

