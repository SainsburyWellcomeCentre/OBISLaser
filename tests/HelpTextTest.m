classdef HelpTextTest < matlab.unittest.TestCase
% HelpTextTest holds every file's help text and line lengths to the repository's standard.
%
%   The standard is CLAUDE.md, Conventions:
%       help      every file starts with help text, right after its function or classdef
%                 line (a script's on its first line)
%       H1        the first help line names the file as MATLAB knows it (obis.Laser for
%                 +obis/Laser.m, example_basic for examples/example_basic.m), says what it
%                 does in one sentence ending in a full stop, and the next help line is blank
%       See also  every file outside tests/ has one, without a colon, and every name on it
%                 that belongs to this repository exists
%       lines     no line longer than 100 characters; comments are ASCII only (a Windows
%                 console drops anything else from help)
%
% See also run_tests

    properties
        Root
        Files
    end

    methods (TestClassSetup)
        function listFiles(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            root = testCase.Root;
            listing = [dir(fullfile(root, '+obis', '**', '*.m'));
                dir(fullfile(root, 'examples', '*.m')); dir(fullfile(root, 'tests', '*.m'))];
            files = struct('Path', {}, 'Relative', {}, 'Name', {});
            for k = 1:numel(listing)
                file = fullfile(listing(k).folder, listing(k).name);
                relative = strrep(file(numel(root) + 2:end), '\', '/');
                parts = strsplit(relative(1:end - 2), '/');
                packages = parts(startsWith(parts, '+'));
                name = strjoin([erase(packages, '+'), parts(end)], '.');
                files(end + 1) = struct('Path', file, 'Relative', relative, ...
                    'Name', name); %#ok<AGROW>
            end
            testCase.Files = files;
            previous = path();
            testCase.addTeardown(@() path(previous));
            addpath(fullfile(root, 'examples'), fullfile(root, 'tests'));
        end
    end

    methods (Test)
        function everyFileStartsWithHelpText(testCase)
            problems = {};
            for f = testCase.Files
                help = helpLines(f.Path);
                if isempty(help) || isempty(strtrim(help{1}))
                    problems{end + 1} = f.Relative; %#ok<AGROW>
                end
            end
            testCase.verifyEmpty(problems, sprintf('No help text:\n  %s', ...
                strjoin(problems, newline)));
        end

        function everyH1NamesItsFileInOneSentence(testCase)
            problems = {};
            for f = testCase.Files
                help = helpLines(f.Path);
                if isempty(help)
                    continue
                end
                h1 = strtrim(help{1});
                if ~startsWith(h1, [f.Name ' '])
                    problems{end + 1} = sprintf('%s: does not start with "%s"', f.Relative, ...
                        f.Name); %#ok<AGROW>
                elseif ~endsWith(h1, '.')
                    problems{end + 1} = sprintf('%s: no full stop', f.Relative); %#ok<AGROW>
                elseif numel(help) > 1 && ~isempty(strtrim(help{2}))
                    problems{end + 1} = sprintf('%s: runs on to a second line', ...
                        f.Relative); %#ok<AGROW>
                end
            end
            testCase.verifyEmpty(problems, sprintf('H1 lines:\n  %s', ...
                strjoin(problems, newline)));
        end

        function everyFileOutsideTestsHasASeeAlsoLine(testCase)
            problems = {};
            for f = testCase.Files
                if ~startsWith(f.Relative, 'tests/') && isempty(seeAlso(helpLines(f.Path)))
                    problems{end + 1} = f.Relative; %#ok<AGROW>
                end
            end
            testCase.verifyEmpty(problems, sprintf('No See also line:\n  %s', ...
                strjoin(problems, newline)));
        end

        function seeAlsoNamesExist(testCase)
            local = {testCase.Files.Name};
            problems = {};
            for f = testCase.Files
                text = fileread(f.Path);
                if ~isempty(regexp(text, '^\s*%\s*See also:', 'once', 'lineanchors'))
                    problems{end + 1} = sprintf('%s: "See also:" with a colon', ...
                        f.Relative); %#ok<AGROW>
                end
                for item = seeAlso(helpLines(f.Path))
                    name = item{1};
                    ours = startsWith(name, 'obis.') || ismember(name, local);
                    if ours && ~nameExists(name)
                        problems{end + 1} = sprintf('%s: %s', f.Relative, name); %#ok<AGROW>
                    end
                end
            end
            testCase.verifyEmpty(problems, sprintf('See also problems:\n  %s', ...
                strjoin(problems, newline)));
        end

        function linesAreShortAndCommentsAreAscii(testCase)
            problems = {};
            for f = testCase.Files
                lines = splitlines(string(fileread(f.Path)));
                for k = 1:numel(lines)
                    line = lines(k);
                    if strlength(line) > 100
                        problems{end + 1} = sprintf('%s:%d: %d characters', f.Relative, k, ...
                            strlength(line)); %#ok<AGROW>
                    end
                    comment = extractAfter(line, '%');
                    if ~ismissing(comment) && any(double(char(comment)) > 127)
                        problems{end + 1} = sprintf('%s:%d: not ASCII', f.Relative, ...
                            k); %#ok<AGROW>
                    end
                end
            end
            testCase.verifyEmpty(problems, sprintf('Lines:\n  %s', strjoin(problems, newline)));
        end
    end
end


function lines = helpLines(file)
% The help text: the comment block after the declaration (or a script's first lines).
text = splitlines(string(fileread(file)));
first = 2;
if startsWith(strtrim(text(1)), '%')
    first = 1;
end
lines = {};
for k = first:numel(text)
    line = strtrim(text(k));
    if ~startsWith(line, '%')
        break
    end
    lines{end + 1} = char(extractAfter(line, 1)); %#ok<AGROW>
end
end


function items = seeAlso(help)
% The names on the help's See also line and its continuation lines.
items = {};
for k = 1:numel(help)
    line = strtrim(help{k});
    if startsWith(line, 'See also')
        rest = extractAfter(line, 'See also');
        for j = k + 1:numel(help)
            if isempty(strtrim(help{j}))
                break
            end
            rest = [rest ' ' help{j}]; %#ok<AGROW>
        end
        items = regexp(rest, '[\w.]+', 'match');
        return
    end
end
end


function tf = nameExists(name)
% True when name is a function, class, script or a method of a class on the path.
tf = ~isempty(which(name)) || exist(name, 'class') > 0 || ~isempty(meta.package.fromName(name));
if tf
    return
end
dot = find(name == '.', 1, 'last');
if isempty(dot)
    return
end
owner = meta.class.fromName(name(1:dot - 1));
tf = ~isempty(owner) && any(strcmp({owner.MethodList.Name}, name(dot + 1:end)));
end
