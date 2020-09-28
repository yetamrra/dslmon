--
-- PostgreSQL database dump
--

SET default_tablespace = '';

--
-- Name: uplog; Type: TABLE; Schema: public; Owner: dslmon
--

CREATE TABLE public.uplog (
    logtime timestamp with time zone NOT NULL,
    dsltime timestamp without time zone NOT NULL,
    ip inet NOT NULL,
    uptime character varying(20),
    kbps_dn integer,
    kbps_up integer
);


--
-- Name: uplog uplog_pkey; Type: CONSTRAINT; Schema: public; Owner: dslmon
--

ALTER TABLE ONLY public.uplog
    ADD CONSTRAINT uplog_pkey PRIMARY KEY (logtime);


--
-- PostgreSQL database dump complete
--

