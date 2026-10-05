function results = run_tests(varargin)
% run_tests runs the obis test suite headless, with no hardware.
%
%   results = run_tests() runs every test class in this folder and prints a summary.
%   results = run_tests('Filter', 'Laser') runs the classes whose name contains Filter.
%   results = run_tests('Verbosity', 2) passes a verbosity to the test runner.
%
%   tests/hardware/ is not run: those scripts drive the real laser and need the operator's
%   permission (CLAUDE.md, Hardware).
%
%   From the operating-system shell:
%       matlab -batch "cd tests; results = run_tests; exit(any([results.Failed]))"
%
% See also runtests
    parser = inputParser;
    parser.addParameter('Filter', '', @(x) ischar(x) || isstring(x));
    parser.addParameter('Verbosity', 1, @isnumeric);
    parser.parse(varargin{:});

    testDir = fileparts(mfilename('fullpath'));
    packageDir = fileparts(testDir);
    previous = path();
    restore = onCleanup(@() path(previous));
    addpath(packageDir);

    suite = matlab.unittest.TestSuite.fromFolder(testDir);
    if ~isempty(parser.Results.Filter)
        names = string({suite.Name});
        suite = suite(contains(names, string(parser.Results.Filter)));
    end
    runner = matlab.unittest.TestRunner.withTextOutput('Verbosity', parser.Results.Verbosity);
    results = runner.run(suite);
    fprintf('\n%d tests: %d passed, %d failed, %d incomplete (%.1f s)\n', numel(results), ...
        sum([results.Passed]), sum([results.Failed]), sum([results.Incomplete]), ...
        sum([results.Duration]));
end
