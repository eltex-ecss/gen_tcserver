.PHONY: all deps compile test eunit clean travis

REBAR?=${PWD}/rebar
RELX?=${PWD}/relx

all: deps compile test dialyze

deps:
	@REBAR_EXTRA_DEPS=1 rebar get-deps u-d

compile:
	rebar compile

test: eunit

eunit:
	rebar eunit skip_deps=true

dialyze: .rebar/*.plt
	rebar dialyze

.rebar/*.plt:
	rebar build-plt

travis:
	@REBAR_EXTRA_DEPS=1 $(REBAR) get-deps compile
	$(REBAR) eunit skip_deps=true

clean:
	rebar clean
	-rm -rf .rebar