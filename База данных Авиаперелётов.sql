-- Названия самолетов, которые имеют менее 50 посадочных мест.

select aircraft_code, count(*)
from seats 
group by aircraft_code
having count(*) < 50

------------------------------------------------------------------------------------------------------------------------
​
-- Процентное изменение ежемесячной суммы бронирования билетов, округленной до сотых.

select date_trunc('month', book_date), sum(total_amount),
	round(sum(total_amount) * 100 / (lag(sum(total_amount)) over (order by date_trunc('month', book_date))) - 100, 2)
from bookings b
group by date_trunc('month', book_date)
​
------------------------------------------------------------------------------------------------------------------------

-- Названия самолетов не имеющие бизнес класс.

select aircraft_code, array_agg(fare_conditions) 
from seats 
group by aircraft_code
having not array['Business'::varchar] && array_agg(fare_conditions)

------------------------------------------------------------------------------------------------------------------------

-- Накопительный итог количества мест в самолетах по каждому аэропорту на каждый день, учитывая только
-- те самолеты, которые летали пустыми и только те дни, где из одного аэропорта таких самолетов вылетало более одного.

-- CTE "c": выбираем пустые рейсы (на них нет посадочных талонов)
with c as (
	select departure_airport, actual_departure, actual_departure::date ad_date, c_s
	from flights f
	join (
		-- Считаем количество мест в каждом типе самолёта
		select aircraft_code, count(*) c_s
		from seats
		group by aircraft_code
		) s on s.aircraft_code = f.aircraft_code -- Присоединяем данные о вместимости по коду самолёта
	left join boarding_passes bp on bp.flight_id = f.flight_id
	where actual_departure is not null -- Учитываем только реально вылетевшие рейсы
	and bp.flight_id is null -- И только те, где не было ни одного посадочного талона
)
select departure_airport, ad_date, c_s,
-- Накопительный итог мест по аэропорту и дате, сортировка по времени вылета
sum(c_s) over (partition by departure_airport, ad_date order by actual_departure)
from c 
-- Учитываем только те дни и аэропорты, где было больше одного пустого рейса
where (departure_airport, ad_date) in (
	select departure_airport, ad_date
	from c 
	group by 1,2 
	having count(*) > 1)
	
	------------------------------------------------------------------------------------------------------------------------
	
-- Классификация финансовых оборотов (сумма стоимости билетов) по маршрутам:
-- • До 50 млн - low
-- • От 50 млн включительно до 150 млн - middle
-- • От 150 млн включительно - high
-- + количество маршрутов в каждом полученном классе.

select c, count(*)
from (
	select 
		case 
			when sum(tf.amount) < 50000000 then 'low'
			when sum(tf.amount) >= 50000000 and sum(tf.amount) < 150000000 then 'middle'
			else 'high'
		end c
	from flights f 
	join ticket_flights tf on tf.flight_id = f.flight_id 
	group by flight_no) t
group by c

------------------------------------------------------------------------------------------------------------------------

-- Вычисление медианы стоимости билетов, медианы размера бронирования и отношение медианы бронирования к медиане стоимости билетов, округленной до сотых.

select 
    t2.mediana_bookings,                                -- Медиана суммы бронирований
    t1.mediana_tickets,                                 -- Медиана стоимости билетов
    round(t2.mediana_bookings / t1.mediana_tickets, 2)  -- Отношение медиан, округлённое до сотых
from 
    (
        -- Находим медиану стоимости билетов
        select percentile_cont(0.5) within group(order by amount)::numeric as mediana_tickets 
        from ticket_flights
    ) t1,
    (
        -- Находим медиану суммы бронирований
        select percentile_cont(0.5) within group(order by total_amount)::numeric as mediana_bookings 
        from bookings
    ) t2

------------------------------------------------------------------------------------------------------------------------

-- Значение минимальной стоимости полета 1 км для пассажиров. Необходимо найти расстояние между аэропортами и, с учетом стоимости билетов, получить искомый результат.
    
-- Подключаем расширения для работы с географией:
-- cube — для работы с многомерными точками (координаты)
-- earthdistance — для вычисления расстояний между точками на сфере (в метрах)
create extension cube;
create extension earthdistance;

-- Основной запрос: вычисляем минимальную стоимость полёта за 1 км
select 
    tf.min / (
        earth_distance(
            ll_to_earth(d.latitude, d.longitude),     -- Координаты аэропорта вылета
            ll_to_earth(a.latitude, a.longitude)      -- Координаты аэропорта прилёта
        ) / 1000                                      -- Переводим расстояние из метров в километры
    ) as cost_per_km
from (
    -- Для каждого рейса находим минимальную цену билета
    select flight_id, min(amount)
    from ticket_flights 
    group by flight_id
) tf
-- Присоединяем таблицу рейсов, чтобы получить маршруты
join flights f on f.flight_id = tf.flight_id
-- Присоединяем таблицу аэропортов отправления
join airports d on f.departure_airport = d.airport_code
-- Присоединяем таблицу аэропортов прибытия
join airports a on f.arrival_airport = a.airport_code
-- Сортируем по стоимости за км (от самой низкой)
order by 1
-- Берём только самый дешёвый вариант
limit 1;

