create table parkove_gradini_bgs as
select id, st_transform(wkb_geometry, 7801) as geom from parkove_gradini_26_sofpr_20200914 pgs

create table peshehodna_mreja_bgs(id, geom, minutes) as
select row_number() over (order by id), st_transform((st_dump(wkb_geometry)).geom, 7801), minutes as geom from peshehodna_mreja_25_sofpr_20190820 pms;

create table parkove_gradini_vhod_bgs as
select id, st_transform(wkb_geometry, 7801) as geom from parkove_gradini_vhod_26_sofpr_20200914 pgvs 

create table parkove_gradini_filtrirani_bgs(id, geom) as
select distinct pgb.id, pgb.geom from parkove_gradini_bgs pgb 
inner join peshehodna_mreja_bgs pmb
on st_dwithin(pmb.geom, pgb.geom, 20)
inner join parkove_gradini_vhod_bgs pgvb
on st_dwithin(pgb.geom, pgvb.geom, 5);

pgr_nodeNetwork('peshehodna_mreja_bgs', 2,'id','geom')

create table peshehodna_mreja_bgs_noded_costs as  
select pmbn.id, pmbn.source, pmbn.target, pmbn.geom, pmb.minutes * (st_length(pmbn.geom) / st_length(pmb.geom)) as minutes from peshehodna_mreja_bgs_noded pmbn
inner join peshehodna_mreja_bgs pmb
on pmb.id = pmbn.old_id;

select pgr_createtopology('peshehodna_mreja_bgs_noded_costs', 2, 'geom');
select pgr_analyzegraph('peshehodna_mreja_bgs_noded_costs', 2, 'geom');

ALTER TABLE peshehodna_mreja_bgs_noded_costs ADD COLUMN x1 double precision;
ALTER TABLE peshehodna_mreja_bgs_noded_costs ADD COLUMN y1 double precision;
ALTER TABLE peshehodna_mreja_bgs_noded_costs ADD COLUMN x2 double precision;
ALTER TABLE peshehodna_mreja_bgs_noded_costs ADD COLUMN y2 double precision;

UPDATE peshehodna_mreja_bgs_noded_costs SET x1 = st_x(ST_startpoint(geom));
UPDATE peshehodna_mreja_bgs_noded_costs SET y1 = st_y(ST_startpoint(geom));

UPDATE peshehodna_mreja_bgs_noded_costs SET x2 = st_x(ST_endpoint(geom));
UPDATE peshehodna_mreja_bgs_noded_costs SET y2 = st_y(ST_endpoint(geom));

create table closest_vertex_to_entry as
select pgvb.id as vhod_id, vertices.id as vertex_id from parkove_gradini_vhod_bgs pgvb
cross join lateral (select pmbncvp.id, pmbncvp.the_geom <-> pgvb.geom as dist
	from peshehodna_mreja_bgs_noded_costs_vertices_pgr pmbncvp 
	order by dist
	limit 1
) vertices;

create table entries_by_park (entry_id, park_id) as
select pgvb.id, pgfb.id from parkove_gradini_vhod_bgs pgvb
inner join parkove_gradini_filtrirani_bgs pgfb
on st_dwithin(pgvb.geom, pgfb.geom, 5);

create table vertex_entries_to_park as
select cvte.vertex_id, ebp.park_id from entries_by_park ebp
inner join closest_vertex_to_entry cvte
on ebp.entry_id = cvte.vhod_id

create table roads (start_id, end_id, geom) as
select vetp.vertex_id as entrance1, vetp2.vertex_id as entrance2, dijkstra_alg.geom from vertex_entries_to_park vetp
inner join vertex_entries_to_park vetp2
on vetp.park_id != vetp2.park_id
inner join peshehodna_mreja_bgs_noded_costs_vertices_pgr pmbncvp 
on pmbncvp.id = vetp.vertex_id
inner join peshehodna_mreja_bgs_noded_costs_vertices_pgr pmbncvp2 
on pmbncvp2.id = vetp2.vertex_id
cross join lateral (select st_collect(pmb.geom) as geom, sum(cost) as sum_cost from
	pgr_astar('select id, source, target, minutes as cost, x1, y1, x2, y2 from peshehodna_mreja_bgs_noded_costs', vetp.vertex_id, vetp2.vertex_id)
	inner join peshehodna_mreja_bgs_noded_costs pmb
	on edge = pmb.id
) as dijkstra_alg
where vetp.vertex_id != vetp2.vertex_id and st_dwithin(pmbncvp.the_geom, pmbncvp2.the_geom, 500) and dijkstra_alg.sum_cost < 10;
