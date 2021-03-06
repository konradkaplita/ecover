-module(ecover).

-export([compile/0,
         analyse/0,
         merge/0]).

-type coverage() :: tuple(atom(), atom(), integer(), integer()).

pmap(F, L) ->
    Self = self(),
    Pids = [spawn(fun() ->
                          Self ! {self(), F(Element)}
                  end) || Element <- L],
    collect(Pids).

collect([H|T]) ->
    receive
        {H, Ret} ->
            [Ret|collect(T)]
    end;
collect([]) ->
    [].

-spec compile() -> list(tuple(ok, atom())).
compile() ->
    cover:start(),
    pmap(fun(M) ->
                 io:format("Cover compiling: ~p~n", [M]),
                 {ok, M} = cover:compile_beam(M)
         end, get_modules()).

-spec analyse() -> ok.
analyse() ->
    cover:start(),
    CoverPath = filename:join([code:root_dir(), "log", "cover"]),
    ok = filelib:ensure_dir(filename:join([CoverPath, "ensure"])),
    Coverage =
        pmap(fun({M, App}) ->
                     io:format("Cover analysing: ~p~n", [M]),
                     CoverFile = filename:join([CoverPath, atom_to_list(M) ++ ".COVER.html"]),
                     case cover:analyse_to_file(M, CoverFile, [html]) of
                         {ok, CoverFile} ->
                             {ok, {Module, {Covered, NotCovered}}} = cover:analyse(M, coverage, module),
                             {Module, App, Covered, NotCovered};
                         Error ->
                             io:format("Cover analysing error: ~p~n", [M]),
                             case Error of
                                 {error, {file, _Bin, enoent}} ->
                                     io:format("Error: ~p~n", [{error, {file, M, enoent}}]);
                                 _ ->
                                     io:format("Error: ~p~n", [Error])
                             end,
                             {M, App, 0, 0}
                     end
             end, get_applications_for_modules(get_modules())),
    Title = "Acceptance tests coverage",
    cover_write_index(Title, CoverPath, lists:keysort(2, Coverage)),
    CoverData = filename:join([CoverPath, "acceptance-all.coverdata"]),
    cover:export(CoverData).

merge() ->
    cover:start(),
    CoverTotalPath = filename:join([code:root_dir(), "log", "cover", "total"]),
    ok = filelib:ensure_dir(filename:join([CoverTotalPath, "ensure"])),
    import_acceptance_coverage(),
    import_unit_coverage(),
    Coverage =
        pmap(fun({M, App}) ->
                     io:format("Cover merging: ~p~n", [M]),
                     CoverFile = filename:join([CoverTotalPath, atom_to_list(M) ++ ".COVER.html"]),
                     case cover:analyse_to_file(M, CoverFile, [html]) of
                         {ok, CoverFile} ->
                             {ok, {Module, {Covered, NotCovered}}} = cover:analyse(M, coverage, module),
                             {Module, App, Covered, NotCovered};
                         Error ->
                             io:format("Cover analysing error: ~p~n", [M]),
                             io:format("Error: ~p~n", [Error]),
                             {M, App, 0, 0}
                     end
             end, get_applications_for_modules(cover:imported_modules())),
    Title = "Total tests coverage",
    cover_write_index(Title, CoverTotalPath, lists:keysort(2, Coverage)),
    CoverData = filename:join([CoverTotalPath, "total-all.coverdata"]),
    io:format("Saving total coverdata to: ~p~n", [CoverData]),
    cover:export(CoverData).

%% Private functions -----------------------------------------------------------

-spec import_acceptance_coverage() -> ok.
import_acceptance_coverage() ->
    CoverPath = filename:join([code:root_dir(),
                               "log",
                               "cover"]),
    CoverAcceptanceData = filename:join([CoverPath, "acceptance-all.coverdata"]),
    io:format("Cover acceptance path: ~p~n", [CoverAcceptanceData]),
    cover:import(CoverAcceptanceData).

-spec import_unit_coverage() -> ok.
import_unit_coverage() ->
    lists:foreach(fun(CoverCtPath) ->
                          io:format("Cover unit CT path: ~p~n", [CoverCtPath]),
                          cover:import(CoverCtPath)
                  end, list_unit_coverdata()).

-spec list_unit_coverdata() -> list(string()).
list_unit_coverdata() ->
    {ok, AppsConfigs} = application:get_env(ecover, apps),
    lists:map(fun([_, {coverdata_path, Path}]) ->
                      AppLogsDir = filename:join([code:root_dir(), "..", Path, "logs"]),
                      Ret = string:strip(os:cmd("find " ++ AppLogsDir ++ " -name all.coverdata | sort | tail -1"), right, $\n),
                      io:format("Found CT coverdata file: ~p~n", [Ret]),
                      Ret
              end, AppsConfigs).


-spec get_modules() -> list(atom()).
get_modules() ->
    {ok, AppsConfigs} = application:get_env(ecover, apps),
    lists:foldl(fun([{name, Pattern}, _], Acc) ->
                        P = code:root_dir() ++ "/lib/" ++ Pattern ++ "-*/ebin/*.beam",
                        Files = filelib:wildcard(P),
                        Mods = [begin
                                    B = filename:basename(F),
                                    [Mod, "beam"] = re:split(B, "\\.", [{return, list}]),
                                    list_to_atom(Mod)
                                end || F <- Files],
                        Acc ++ Mods
                end, [], AppsConfigs).

-spec get_applications_for_modules(list(atom())) -> list(tuple(atom(), atom())).
get_applications_for_modules(Modules) ->
    lists:map(fun(M) ->
                      try
                          Path = proplists:get_value(source, M:module_info(compile), ""),
                          L = re:split(Path, "/", [{return, list}]),
                          AppName = list_to_atom(lists:nth(length(L) - 2, L)),
                          {M, AppName}
                      catch
                          _:_ ->
                              {M, xx_unknown_app_xx}
                      end
              end, Modules).

-spec cover_write_index(string(), string(), list(coverage())) -> ok.
cover_write_index(Title, CoverPath, Coverage) ->
    {ok, F} = file:open(filename:join([CoverPath, "index.html"]), [write]),
    ok = file:write(F, "<html><head><title>Coverage Summary</title></head>\n"),
    cover_write_index_section(F, Title, Coverage),
    ok = file:write(F, "</body></html>"),
    ok = file:close(F).

-spec cover_write_index_section(file:io_device(), string(), list(coverage())) -> ok.
cover_write_index_section(_F, _SectionName, []) ->
    ok;
cover_write_index_section(F, SectionName, Coverage) ->
    TotalCoverage = total_coverage(Coverage),
    %% Write the report
    ok = file:write(F, io_lib:format("<body><h1>~s summary</h1>\n", [SectionName])),
    ok = file:write(F, io_lib:format("<h3>Total: ~s</h3>\n", [TotalCoverage])),
    ok = file:write(F, "<table><tr><th>Module</th><th>Coverage %</th></tr>\n"),

    lists:foldl(fun({Module, CurrentApp, Cov, NotCov}, CurrentApp) ->
                        write_link(F, Module, Cov, NotCov),
                        CurrentApp;
                   ({Module, NewApp, Cov, NotCov}, _CurrentApp) ->
                        cover_write_app_section(F, NewApp, Coverage),
                        write_link(F, Module, Cov, NotCov),
                        NewApp
                end, undefined, Coverage),
    ok = file:write(F, "</table>\n").

-spec cover_write_app_section(file:io_device(), atom(), list(coverage())) -> ok.
cover_write_app_section(File, App, Coverage) ->
    AppCoverage = total_app_coverage(App, Coverage),
    ok = file:write(File, io_lib:format("<tr><th>~s</th><th>~s</th></tr>\n",
                                        [App, AppCoverage])).

-spec write_link(file:io_device(), atom(), integer(), integer()) -> ok.
write_link(File, Module, Covered, NotCovered) ->
    FmtLink = fun() ->
                      io_lib:format("<tr><td><a href='~s.COVER.html'>~s</a></td><td>~s</td>\n",
                                    [Module, Module, percentage(Covered, NotCovered)])
              end,
    ok = file:write(File, FmtLink()).

-spec total_coverage(list(coverage())) -> string().
total_coverage(Coverage) ->
    {Covered, NotCovered} = lists:foldl(fun({_Mod, _App, C, N}, {CAcc, NAcc}) ->
                                                {CAcc + C, NAcc + N}
                                    end, {0, 0}, Coverage),
    percentage(Covered, NotCovered).

-spec total_app_coverage(atom(), list(coverage())) -> string().
total_app_coverage(App, Coverage) ->
    AppCoverage = lists:filter(fun({_Mod, A, _Cov, _NCov}) when A =:= App ->
                                       true;
                                  (_) ->
                                       false
                               end, Coverage),
    total_coverage(AppCoverage).

-spec percentage(integer(), integer()) -> string().
percentage(0, 0) ->
    "not executed";
percentage(Cov, NotCov) ->
    integer_to_list(trunc((Cov / (Cov + NotCov)) * 100)) ++ "%".
